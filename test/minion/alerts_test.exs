defmodule Minion.AlertsTest do
  use Minion.DataCase, async: true

  import Minion.AlertFixtures

  alias Minion.Alerts
  alias Minion.Alerts.Alert

  setup do
    team = team_fixture()
    %{team: team, rule: rule_fixture(team)}
  end

  describe "acknowledge/1" do
    test "moves an open alert to acked and tells subscribers", %{rule: rule} do
      alert = alert_fixture(rule)
      Alerts.subscribe(alert)

      assert {:ok, %Alert{status: :acked}} = Alerts.acknowledge(alert.id)
      assert_received {:alert, :acked, %Alert{status: :acked}}
    end

    test "when two people acknowledge at once, only the first succeeds", %{rule: rule} do
      alert = alert_fixture(rule)

      assert {:ok, _} = Alerts.acknowledge(alert.id)
      assert {:error, :not_open} = Alerts.acknowledge(alert.id)
    end

    test "cannot acknowledge a resolved alert", %{rule: rule} do
      alert = alert_fixture(rule, %{status: :resolved})

      assert {:error, :not_open} = Alerts.acknowledge(alert.id)
    end
  end

  describe "resolve/1" do
    test "resolves an open or acknowledged alert and tells subscribers", %{rule: rule} do
      open = alert_fixture(rule)
      acked = alert_fixture(rule, %{status: :acked})
      Alerts.subscribe(open)

      assert {:ok, %Alert{status: :resolved}} = Alerts.resolve(open.id)
      assert {:ok, %Alert{status: :resolved}} = Alerts.resolve(acked.id)
      assert_received {:alert, :resolved, %Alert{}}
    end

    test "resolving twice reports that it is already resolved", %{rule: rule} do
      alert = alert_fixture(rule)

      assert {:ok, _} = Alerts.resolve(alert.id)
      assert {:error, :already_resolved} = Alerts.resolve(alert.id)
    end
  end

  test "list_recent/1 returns the most recently active alerts first, with their rule", %{
    rule: rule
  } do
    older = alert_fixture(rule, %{last_seen: ~U[2026-11-20 10:00:00.000000Z]})
    newer = alert_fixture(rule, %{last_seen: ~U[2026-11-20 11:00:00.000000Z]})

    assert [%Alert{id: first_id, rule: %{name: "Disk full"}}, %Alert{id: second_id}] =
             Alerts.list_recent()

    assert {first_id, second_id} == {newer.id, older.id}
  end

  test "owner_names/0 names teams and people", %{team: team} do
    anna = person_fixture(team, "Anna")
    names = Alerts.owner_names()

    assert names[{:team, team.id}] == team.name
    assert names[{:person, anna.id}] == "Anna"
  end
end
