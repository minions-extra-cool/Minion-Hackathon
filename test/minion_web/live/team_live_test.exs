defmodule MinionWeb.TeamLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Accounts

  setup do
    team = team_fixture()
    anna = person_fixture(team, "Anna")
    piotr = person_fixture(team, "Piotr")
    {:ok, team} = Accounts.update_team(team, %{auto_resolve_after: %{"warning" => 14_400}})
    %{team: team, anna: anna, piotr: piotr, rule: rule_fixture(team)}
  end

  test "the teams list explains teams and shows members, on-call and auto-resolve", %{
    conn: conn,
    team: team
  } do
    {:ok, view, _html} = live(conn, ~p"/teams")

    assert has_element?(view, "#nav-teams")
    assert has_element?(view, "#teams-explainer", "A team owns rules")
    assert has_element?(view, "#team-#{team.id}", "Anna, Piotr")
    assert has_element?(view, "#team-#{team.id}", "On call: nobody")
    assert has_element?(view, "#team-#{team.id}", "warning after 4 hours quiet")
    assert has_element?(view, "#team-#{team.id}", "1 rule")
  end

  test "creating a team opens its page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teams")

    {:ok, _team_view, html} =
      view
      |> form("#new-team-form", team: %{name: "payments"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "payments"
  end

  test "the team page lists members and rules, and saves settings", %{
    conn: conn,
    team: team,
    piotr: piotr,
    rule: rule
  } do
    {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")

    assert has_element?(view, "#member-#{piotr.id} a[href='/people/#{piotr.id}']", "Piotr")
    assert has_element?(view, "#team-rules a[href='/rules/#{rule.id}']", rule.name)
    assert has_element?(view, "#team-warning-minutes[value='240']")

    view
    |> form("#team-form", team: %{oncall_person_id: piotr.id, warning: "30", info: "10"})
    |> render_submit()

    saved = Accounts.get_team!(team.id)
    assert saved.oncall_person_id == piotr.id
    assert saved.auto_resolve_after == %{"warning" => 1800, "info" => 600}
    assert has_element?(view, "#member-#{piotr.id}", "on call")
    assert has_element?(view, "#team-auto-resolve", "warning after 30 minutes quiet")
  end

  test "an empty minutes field means never", %{conn: conn, team: team} do
    {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")

    view |> form("#team-form", team: %{warning: "", info: ""}) |> render_submit()

    assert Accounts.get_team!(team.id).auto_resolve_after == %{}
    assert has_element?(view, "#team-auto-resolve", "Never auto-resolves")
  end

  test "a nonsense time is refused", %{conn: conn, team: team} do
    {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")

    html = view |> form("#team-form", team: %{warning: "-5"}) |> render_submit()

    assert html =~ "invalid entry"
    assert Accounts.get_team!(team.id).auto_resolve_after == %{"warning" => 14_400}
  end

  test "adding a person takes you to their notifications", %{conn: conn, team: team} do
    {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")

    {:ok, _person_view, html} =
      view
      |> form("#add-person-form", person: %{name: "Zofia", email: "zofia@minion.test"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Zofia"
    assert html =~ "Set how they want to be notified"
    assert [%{team_id: team_id}] = Enum.filter(Accounts.list_people(), &(&1.name == "Zofia"))
    assert team_id == team.id
  end

  describe "webhook key" do
    test "a team without a key is told posts are refused", %{conn: conn, team: team} do
      {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")

      assert has_element?(view, "#ingest-key-missing")
      assert has_element?(view, "#generate-ingest-key", "Generate key")
    end

    test "generating shows the key once, and it works for ingest", %{conn: conn, team: team} do
      {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")

      view |> element("#generate-ingest-key") |> render_click()

      [key] =
        Regex.run(~r/mk_[\w-]{32}/, view |> element("#new-ingest-key-value") |> render())

      assert Accounts.team_for_ingest_key(key).id == team.id

      {:ok, view, html} = live(conn, ~p"/teams/#{team.id}")
      refute html =~ key
      assert has_element?(view, "#ingest-key-status", "…" <> String.slice(key, -4, 4))
      assert has_element?(view, "#generate-ingest-key[data-confirm]", "Generate a new key")

      view |> element("#generate-ingest-key") |> render_click()
      assert Accounts.team_for_ingest_key(key) == nil
    end
  end
end
