defmodule Minion.Alerts.Processor do
  alias Minion.Alerts
  alias Minion.Alerts.Alert
  alias Minion.Delivery
  alias Minion.Repo
  alias Minion.Rules.{Fingerprint, Matcher, Rule, Template}

  @unresolved_fingerprint {:unsafe_fragment, "(fingerprint) WHERE status <> 'resolved'"}

  @type outcome :: {:created | :updated, Alert.t()}

  @spec process(map(), [Rule.t()], keyword()) :: {:ok, [outcome()]} | {:error, term()}
  def process(envelope, rules, opts \\ []) do
    dispatch = Keyword.get(opts, :dispatch, &Delivery.dispatch/1)

    case Enum.filter(rules, &Matcher.matches?(&1.conditions, envelope)) do
      [] ->
        {:ok, []}

      matched ->
        now = DateTime.utc_now()

        with {:ok, outcomes} <-
               Repo.transaction(fn -> Enum.map(matched, &record(&1, envelope, now, dispatch)) end) do
          Enum.each(outcomes, &broadcast/1)
          {:ok, outcomes}
        end
    end
  end

  defp record(rule, envelope, now, dispatch) do
    case upsert(rule, envelope, now) do
      {:created, alert} ->
        case dispatch.(alert) do
          :ok -> {:created, alert}
          {:error, reason} -> Repo.rollback({:dispatch_failed, reason})
        end

      updated ->
        updated
    end
  end

  defp upsert(rule, envelope, now) do
    id = Ecto.UUID.generate()
    present = rule.present || %{}

    alert = %Alert{
      id: id,
      rule_id: rule.id,
      owner_type: rule.owner_type,
      owner_id: rule.owner_id,
      fingerprint: Fingerprint.compute(rule, envelope),
      status: :open,
      severity: rule.severity,
      count: 1,
      first_seen: now,
      last_seen: now,
      title: render_title(present["title"], rule.name, envelope),
      body: Template.render(present["body"], envelope),
      sample_event: envelope
    }

    saved =
      Repo.insert!(alert,
        on_conflict: [inc: [count: 1], set: [last_seen: now, updated_at: now]],
        conflict_target: @unresolved_fingerprint,
        returning: true
      )

    if saved.id == id, do: {:created, saved}, else: {:updated, saved}
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
