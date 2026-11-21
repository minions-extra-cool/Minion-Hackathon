defmodule Minion.AlertFixtures do
  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.Alert
  alias Minion.Delivery.Delivery
  alias Minion.Repo
  alias Minion.Rules.Rule

  def team_fixture(name \\ "ops-#{System.unique_integer([:positive])}"),
    do: Repo.insert!(%Team{name: name})

  def person_fixture(team, name \\ "Anna"),
    do:
      Repo.insert!(%Person{
        team_id: team.id,
        name: name,
        email: "#{String.downcase(name)}@minion.test"
      })

  def rule_fixture(team, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Rule{
          name: "Disk full",
          owner_type: :team,
          owner_id: team.id,
          severity: :warning,
          conditions: %{"field" => "payload.type", "op" => "eq", "value" => "DISK_FULL"},
          dedup: %{"key" => ["payload.host"]},
          present: %{"title" => "Disk full on {{payload.host}}", "color" => "amber"},
          notify: []
        },
        attrs
      )
    )
  end

  def alert_fixture(rule, attrs \\ %{}) do
    now = DateTime.utc_now()

    Repo.insert!(
      struct(
        %Alert{
          rule_id: rule.id,
          owner_type: rule.owner_type,
          owner_id: rule.owner_id,
          fingerprint: Ecto.UUID.generate(),
          status: :open,
          severity: rule.severity,
          count: 1,
          first_seen: now,
          last_seen: now,
          title: "Disk full on web-1",
          body: "web-1 reported a full disk.",
          sample_event: %{
            "id" => Ecto.UUID.generate(),
            "source" => "ops-monitor",
            "source_type" => "http",
            "received_at" => DateTime.to_iso8601(now),
            "payload" => %{"type" => "DISK_FULL", "host" => "web-1"}
          }
        },
        attrs
      )
    )
  end

  def delivery_fixture(alert, person, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Delivery{alert_id: alert.id, person_id: person.id, channel: :email, status: :pending},
        attrs
      )
    )
  end
end
