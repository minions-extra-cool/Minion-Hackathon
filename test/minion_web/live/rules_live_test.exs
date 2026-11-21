defmodule MinionWeb.RulesLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Repo
  alias Minion.Rules.Rule

  setup do
    team = team_fixture()
    %{team: team, rule: rule_fixture(team)}
  end

  test "lists rules with a readable summary of their conditions", %{conn: conn, rule: rule} do
    {:ok, view, _html} = live(conn, ~p"/rules")

    assert has_element?(view, "#rules-#{rule.id} a", "Disk full")
    assert has_element?(view, "#rules-#{rule.id}", "payload.type equals DISK_FULL")
    assert has_element?(view, "#rules-#{rule.id} [data-severity=warning][data-enabled=true]")
    assert has_element?(view, "#nav-rules")
  end

  test "shows channels a rule fixes next to who it notifies", %{conn: conn, team: team} do
    rule =
      rule_fixture(team, %{
        name: "Payments down",
        notify: [%{"type" => "oncall", "id" => team.id, "channels" => ["sms", "phone"]}]
      })

    {:ok, view, _html} = live(conn, ~p"/rules")

    assert has_element?(
             view,
             "#rules-#{rule.id}",
             "On call for #{team.name} · by SMS, phone call"
           )
  end

  test "the switch disables and re-enables a rule", %{conn: conn, rule: rule} do
    {:ok, view, _html} = live(conn, ~p"/rules")

    view |> element("#rules-#{rule.id}-enabled") |> render_click()
    assert Repo.get!(Rule, rule.id).enabled == false
    assert has_element?(view, "#rules-#{rule.id} [data-enabled=false]")

    view |> element("#rules-#{rule.id}-enabled") |> render_click()
    assert Repo.get!(Rule, rule.id).enabled == true
  end

  test "New rule opens the editor", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules")

    assert {:error, {:live_redirect, %{to: "/rules/new"}}} =
             view |> element("#new-rule") |> render_click()
  end
end
