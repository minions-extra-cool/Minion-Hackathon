defmodule Minion.AlertsTest do
  use Minion.DataCase, async: true

  import Minion.AlertFixtures

  alias Minion.Alerts
  alias Minion.Alerts.Alert

  setup do
    team = team_fixture()
    %{team: team, rule: rule_fixture(team), anna: person_fixture(team, "Anna")}
  end

  describe "acknowledge/2" do
    test "moves an open alert to acked, records who and when, and tells subscribers", %{
      rule: rule,
      anna: anna
    } do
      alert = alert_fixture(rule)
      Alerts.subscribe(alert)

      assert {:ok, %Alert{status: :acked, acked_at: %DateTime{}} = acked} =
               Alerts.acknowledge(alert.id, anna.id)

      assert acked.acked_by_id == anna.id
      assert_received {:alert, :acked, %Alert{status: :acked}}
    end

    test "when two people acknowledge at once, only the first succeeds", %{
      rule: rule,
      team: team,
      anna: anna
    } do
      alert = alert_fixture(rule)
      piotr = person_fixture(team, "Piotr")

      assert {:ok, _} = Alerts.acknowledge(alert.id, anna.id)
      assert {:error, :not_open} = Alerts.acknowledge(alert.id, piotr.id)
      assert Alerts.get_alert(alert.id).acked_by_id == anna.id
    end

    test "cannot acknowledge a resolved alert", %{rule: rule, anna: anna} do
      alert = alert_fixture(rule, %{status: :resolved})

      assert {:error, :not_open} = Alerts.acknowledge(alert.id, anna.id)
    end
  end

  describe "resolve/2" do
    test "resolves an open or acknowledged alert, records who and when, and tells subscribers",
         %{rule: rule, anna: anna} do
      open = alert_fixture(rule)
      acked = alert_fixture(rule, %{status: :acked})
      Alerts.subscribe(open)

      assert {:ok, %Alert{status: :resolved, resolved_at: %DateTime{}} = resolved} =
               Alerts.resolve(open.id, anna.id)

      assert resolved.resolved_by_id == anna.id
      assert {:ok, %Alert{status: :resolved}} = Alerts.resolve(acked.id, anna.id)
      assert_received {:alert, :resolved, %Alert{}}
    end

    test "resolving twice reports that it is already resolved", %{rule: rule, anna: anna} do
      alert = alert_fixture(rule)

      assert {:ok, _} = Alerts.resolve(alert.id, anna.id)
      assert {:error, :already_resolved} = Alerts.resolve(alert.id, anna.id)
    end
  end

  describe "save_resolution_note/2" do
    test "stores a trimmed note on a resolved alert and tells subscribers", %{
      rule: rule,
      anna: anna
    } do
      alert = alert_fixture(rule)
      {:ok, _} = Alerts.resolve(alert.id, anna.id)
      Alerts.subscribe(alert)

      assert {:ok, %Alert{resolution_note: "Cleared /var/log"}} =
               Alerts.save_resolution_note(alert.id, "  Cleared /var/log\n")

      assert_received {:alert, :updated, %Alert{resolution_note: "Cleared /var/log"}}
    end

    test "a blank note is stored as no note", %{rule: rule, anna: anna} do
      alert = alert_fixture(rule)
      {:ok, _} = Alerts.resolve(alert.id, anna.id)

      assert {:ok, %Alert{resolution_note: nil}} = Alerts.save_resolution_note(alert.id, "  ")
    end

    test "an unresolved alert takes no note", %{rule: rule} do
      alert = alert_fixture(rule)

      assert {:error, :not_resolved} = Alerts.save_resolution_note(alert.id, "fixed")
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

  test "list_recent_visible/2 keeps alerts owned by the person or their team", %{
    team: team,
    rule: rule
  } do
    anna = person_fixture(team, "Anna")
    loner = Repo.insert!(%Minion.Accounts.Person{name: "Loner"})
    team_alert = alert_fixture(rule)

    anna_alert =
      alert_fixture(rule_fixture(team_fixture(), %{owner_type: :person, owner_id: anna.id}))

    _other_team = alert_fixture(rule_fixture(team_fixture()))

    assert anna |> Alerts.list_recent_visible(10) |> Enum.map(& &1.id) |> Enum.sort() ==
             Enum.sort([team_alert.id, anna_alert.id])

    assert Alerts.list_recent_visible(loner, 10) == []
    assert Alerts.list_recent_visible(nil, 10) == []
    assert Alerts.visible_to?(anna_alert, anna)
    refute Alerts.visible_to?(anna_alert, loner)
  end

  test "owner_names/0 names teams and people", %{team: team} do
    anna = person_fixture(team, "Anna")
    names = Alerts.owner_names()

    assert names[{:team, team.id}] == team.name
    assert names[{:person, anna.id}] == "Anna"
  end
end
