defmodule MinionWeb.RulesLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Repo
  alias Minion.Rules.Rule

  setup %{conn: conn} do
    team = team_fixture()
    person = person_fixture(team)

    %{
      conn: Plug.Test.init_test_session(conn, %{"person_id" => person.id}),
      team: team,
      person: person,
      rule: rule_fixture(team)
    }
  end

  describe "who sees what" do
    test "lists your team's and your own rules, not other teams'", %{
      conn: conn,
      rule: rule,
      person: person
    } do
      personal =
        rule_fixture(team_fixture(), %{name: "Mine", owner_type: :person, owner_id: person.id})

      other = rule_fixture(team_fixture(), %{name: "Theirs"})

      {:ok, view, _html} = live(conn, ~p"/rules")

      assert has_element?(view, "#rules-#{rule.id}")
      assert has_element?(view, "#rules-#{personal.id}")
      refute has_element?(view, "#rules-#{other.id}")
    end

    test "another team's rule does not appear live and cannot be toggled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/rules")
      other = rule_fixture(team_fixture(), %{name: "Theirs"})

      send(view.pid, {:rules_changed, other.id})
      render_hook(view, "toggle", %{"id" => other.id})

      refute has_element?(view, "#rules-#{other.id}")
      assert Repo.get!(Rule, other.id).enabled
    end

    test "nobody picked sees no rules and is asked to pick", %{rule: rule} do
      {:ok, view, _html} = live(build_conn(), ~p"/rules")

      refute has_element?(view, "#rules-#{rule.id}")
      assert has_element?(view, "#rules-empty", "Pick who you are")
    end
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
             "On call for #{team.name} · by SMS, Phone call"
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
