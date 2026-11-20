defmodule Minion.Alerts.AutoResolve do
  import Ecto.Query

  alias Minion.Alerts
  alias Minion.Alerts.Alert
  alias Minion.Repo
  alias Minion.Rules.Rule

  @spec run(DateTime.t()) :: [Alert.t()]
  def run(now \\ DateTime.utc_now()) do
    {_count, resolved} =
      from(a in Alert,
        join: r in Rule,
        on: r.id == a.rule_id,
        where: a.status != :resolved,
        where: fragment("jsonb_typeof(?->'quiet_sec') = 'number'", r.dedup),
        where:
          a.last_seen <
            fragment(
              "?::timestamptz - make_interval(secs => (?->>'quiet_sec')::numeric)",
              ^now,
              r.dedup
            ),
        select: a
      )
      |> Repo.update_all(set: [status: :resolved, updated_at: now])

    Enum.each(resolved, &broadcast/1)
    resolved
  end

  defp broadcast(alert),
    do: Phoenix.PubSub.broadcast(Minion.PubSub, Alerts.topic(alert), {:alert, :resolved, alert})
end
