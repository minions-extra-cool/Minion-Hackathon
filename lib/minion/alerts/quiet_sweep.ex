defmodule Minion.Alerts.QuietSweep do
  import Ecto.Query

  alias Minion.Alerts
  alias Minion.Alerts.Alert
  alias Minion.Repo
  alias Minion.Rules.Rule

  @auto_resolve_sql """
  UPDATE alerts AS a
  SET status = 'resolved', resolved_at = $1::timestamp, closed_at = coalesce(a.closed_at, $1::timestamp), updated_at = $1::timestamp
  FROM teams AS t
  WHERE t.id = coalesce(
          (SELECT p.team_id FROM people AS p WHERE a.owner_type = 'person' AND p.id = a.owner_id),
          a.owner_id)
    AND a.status <> 'resolved'
    AND a.severity <> 'critical'
    AND jsonb_typeof(t.auto_resolve_after -> a.severity::text) = 'number'
    AND a.last_seen < $1::timestamp - make_interval(secs => (t.auto_resolve_after ->> a.severity::text)::numeric)
  RETURNING a.*
  """

  @spec run(DateTime.t()) :: %{closed: [Alert.t()], resolved: [Alert.t()]}
  def run(now \\ DateTime.utc_now()) do
    closed = close_quiet_alerts(now)
    resolved = auto_resolve(now)

    Enum.each(closed, &broadcast(:closed, &1))
    Enum.each(resolved, &broadcast(:resolved, &1))
    Minion.Unmatched.prune(now)

    %{closed: closed, resolved: resolved}
  end

  defp close_quiet_alerts(now) do
    {_count, closed} =
      from(a in Alert,
        join: r in Rule,
        on: r.id == a.rule_id,
        where: a.status != :resolved and is_nil(a.closed_at),
        where: fragment("jsonb_typeof(?->'quiet_sec') = 'number'", r.dedup),
        where:
          a.last_seen <
            fragment(
              "?::timestamp - make_interval(secs => (?->>'quiet_sec')::numeric)",
              ^now,
              r.dedup
            ),
        select: a
      )
      |> Repo.update_all(set: [closed_at: now, updated_at: now])

    closed
  end

  defp auto_resolve(now) do
    %{columns: columns, rows: rows} = Repo.query!(@auto_resolve_sql, [now])
    Enum.map(rows, &Repo.load(Alert, {columns, &1}))
  end

  defp broadcast(event, alert),
    do: Phoenix.PubSub.broadcast(Minion.PubSub, Alerts.topic(alert), {:alert, event, alert})
end
