defmodule Minion.Alerts.Processor do
  import Ecto.Query

  alias Minion.Alerts
  alias Minion.Alerts.Alert
  alias Minion.Delivery
  alias Minion.Repo
  alias Minion.Rules.{Fingerprint, Matcher, Rule, Template}

  @active_fingerprint {:unsafe_fragment,
                       "(fingerprint) WHERE status <> 'resolved' AND closed_at IS NULL"}

  @type outcome :: {:created | :updated, Alert.t()}
  @type candidate :: %{rule: Rule.t(), fingerprint: String.t(), envelope: map()}

  @spec process(map(), [Rule.t()], keyword()) :: {:ok, [outcome()]} | {:error, term()}
  def process(envelope, rules, opts \\ []) do
    case candidates(envelope, rules) do
      [] ->
        Minion.Unmatched.record(envelope)
        {:ok, []}

      candidates ->
        process_batch(candidates, opts)
    end
  end

  @spec candidates(map(), [Rule.t()]) :: [candidate()]
  def candidates(envelope, rules) do
    for rule <- rules, Matcher.matches?(rule.conditions, envelope) do
      %{rule: rule, fingerprint: Fingerprint.compute(rule, envelope), envelope: envelope}
    end
  end

  @spec process_batch([candidate()], keyword()) :: {:ok, [outcome()]} | {:error, term()}
  def process_batch(candidates, opts \\ [])

  def process_batch([], _opts), do: {:ok, []}

  def process_batch(candidates, opts) do
    dispatch = Keyword.get(opts, :dispatch, &Delivery.dispatch/1)
    now = DateTime.utc_now()

    rows =
      candidates
      |> Enum.group_by(& &1.fingerprint)
      |> Enum.map(fn {_fingerprint, [first | _] = group} -> row(first, length(group), now) end)
      |> Enum.sort_by(& &1.fingerprint)

    new_ids = Map.new(rows, &{&1.fingerprint, &1.id})

    with {:ok, outcomes} <-
           Repo.transaction(fn -> upsert_and_dispatch(rows, new_ids, now, dispatch) end) do
      Enum.each(outcomes, &broadcast/1)
      {:ok, outcomes}
    end
  end

  defp upsert_and_dispatch(rows, new_ids, now, dispatch) do
    {_count, alerts} =
      Repo.insert_all(Alert, rows,
        on_conflict: increment_existing(now),
        conflict_target: @active_fingerprint,
        returning: true
      )

    alerts
    |> Enum.sort_by(& &1.fingerprint)
    |> Enum.map(fn alert ->
      if alert.id == new_ids[alert.fingerprint] do
        case dispatch.(alert) do
          :ok -> {:created, alert}
          {:error, reason} -> Repo.rollback({:dispatch_failed, reason})
        end
      else
        {:updated, alert}
      end
    end)
  end

  defp increment_existing(now) do
    from a in Alert,
      update: [
        set: [
          count: fragment("? + EXCLUDED.count", a.count),
          last_seen: fragment("GREATEST(?, EXCLUDED.last_seen)", a.last_seen),
          updated_at: ^now
        ]
      ]
  end

  defp row(%{rule: rule, fingerprint: fingerprint, envelope: envelope}, count, now) do
    present = rule.present || %{}

    %{
      id: Ecto.UUID.generate(),
      rule_id: rule.id,
      owner_type: rule.owner_type,
      owner_id: rule.owner_id,
      fingerprint: fingerprint,
      status: :open,
      severity: rule.severity,
      count: count,
      first_seen: now,
      last_seen: now,
      title: render_title(present["title"], rule.name, envelope),
      body: Template.render(present["body"], envelope),
      sample_event: envelope,
      inserted_at: now,
      updated_at: now
    }
  end

  defp render_title(template, fallback, envelope) do
    case template |> Template.render(envelope) |> String.trim() do
      "" -> fallback
      title -> title
    end
  end

  defp broadcast({event, alert}),
    do: Phoenix.PubSub.broadcast(Minion.PubSub, Alerts.topic(alert), {:alert, event, alert})
end
