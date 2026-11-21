defmodule MinionWeb.RuleEditorLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Repo
  alias Minion.Rules.Rule

  setup do
    team = team_fixture()
    %{team: team}
  end

  defp fill_basic_rule(view) do
    view
    |> form("#rule-form", %{
      "name" => "Payments down",
      "severity" => "critical",
      "c" => %{"0" => %{"field" => "payload.type", "op" => "eq", "value" => "PAYMENTS_DOWN"}},
      "title" => "Payments down in {{payload.region}}",
      "dedup_key" => "payload.region"
    })
    |> render_change()
  end

  test "creates a rule from the visual editor", %{conn: conn, team: team} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")
    fill_basic_rule(view)

    assert {:error, {:live_redirect, %{to: "/rules"}}} =
             view |> form("#rule-form") |> render_submit()

    rule = Repo.get_by!(Rule, name: "Payments down")
    assert rule.severity == :critical
    assert rule.owner_id == team.id

    assert rule.conditions == %{
             "all" => [%{"field" => "payload.type", "op" => "eq", "value" => "PAYMENTS_DOWN"}]
           }

    assert rule.dedup == %{"key" => ["payload.region"], "quiet_sec" => 600}
    assert rule.present["title"] == "Payments down in {{payload.region}}"
  end

  test "a rule can always send by chosen channels instead of preferences", %{
    conn: conn,
    team: team
  } do
    {:ok, view, _html} = live(conn, ~p"/rules/new")
    fill_basic_rule(view)

    view
    |> form("#rule-form", %{"notify" => ["oncall:#{team.id}"], "send_by" => "fixed"})
    |> render_change()

    view |> form("#rule-form", %{"channels" => ["sms", "phone"]}) |> render_change()

    assert {:error, {:live_redirect, %{to: "/rules"}}} =
             view |> form("#rule-form") |> render_submit()

    assert Repo.get_by!(Rule, name: "Payments down").notify == [
             %{"type" => "oncall", "id" => team.id, "channels" => ["sms", "phone"]}
           ]
  end

  test "explains what is missing instead of saving an incomplete rule", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")

    view |> form("#rule-form", %{"name" => "Half done"}) |> render_submit()

    assert has_element?(view, "#rule-errors", "needs a field")
    refute Repo.get_by(Rule, name: "Half done")
  end

  test "ignores the _unused_ markers browsers send for untouched inputs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")

    render_change(view, "change", %{
      "_target" => ["name"],
      "name" => "Still works",
      "_unused_title" => "",
      "g" => %{"root" => "any", "_unused_root" => ""},
      "c" => %{
        "0" => %{"field" => "payload.type", "op" => "eq", "value" => "X", "_unused_value" => ""},
        "_unused_0" => ""
      }
    })

    assert has_element?(view, "#rule-name[value='Still works']")
    assert has_element?(view, "#group-root select option[value=any][selected]")
  end

  test "once errors are shown, they update as the rule is fixed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")

    view |> form("#rule-form") |> render_submit()
    assert has_element?(view, "#rule-errors", "Name can't be blank")

    view |> form("#rule-form", %{"name" => "Fixed"}) |> render_change()
    refute has_element?(view, "#rule-errors", "Name can't be blank")
    assert has_element?(view, "#rule-errors", "needs a field")

    fill_basic_rule(view)
    refute has_element?(view, "#rule-errors")
  end

  test "adds conditions and groups", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")

    view |> element("#add-condition-root") |> render_click()
    assert has_element?(view, "#condition-1")

    view |> element("#add-group") |> render_click()
    assert has_element?(view, "#group-2")
    assert has_element?(view, "#condition-2-0")
  end

  test "the test panel shows which conditions an event meets and the title it would get", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/rules/new")
    fill_basic_rule(view)

    view
    |> form("#test-form", %{"event" => ~s({"type": "PAYMENTS_DOWN", "region": "us-east"})})
    |> render_change()

    assert has_element?(view, "#test-result[data-matches=true]")
    assert has_element?(view, "#condition-0[data-result=true]")
    assert has_element?(view, "#test-title", "Payments down in us-east")

    view |> form("#test-form", %{"event" => ~s({"type": "DISK_FULL"})}) |> render_change()

    assert has_element?(view, "#test-result[data-matches=false]")
    assert has_element?(view, "#condition-0[data-result=false]")
  end

  test "switches to JSON and back, keeping edits made in JSON", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")
    fill_basic_rule(view)

    view |> element("#mode-json") |> render_click()

    json =
      view |> element("#rule-json") |> render() |> LazyHTML.from_fragment() |> LazyHTML.text()

    assert %{"name" => "Payments down", "severity" => "critical"} = Jason.decode!(json)

    edited = json |> Jason.decode!() |> Map.put("name", "Payments outage") |> Jason.encode!()
    view |> form("#json-form", %{"json" => edited}) |> render_change()
    view |> element("#mode-visual") |> render_click()

    assert has_element?(view, "#rule-name[value='Payments outage']")
  end

  test "an unfinished new rule can switch to JSON and back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")

    view |> element("#mode-json") |> render_click()
    view |> element("#mode-visual") |> render_click()

    refute has_element?(view, "#json-error")
    assert has_element?(view, "#rule-form")
    assert has_element?(view, "#condition-0")
  end

  test "JSON with values the editor cannot show keeps you in JSON mode", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")

    view |> element("#mode-json") |> render_click()

    json =
      view |> element("#rule-json") |> render() |> LazyHTML.from_fragment() |> LazyHTML.text()

    edited = json |> Jason.decode!() |> Map.put("severity", "urgent") |> Jason.encode!()
    view |> form("#json-form", %{"json" => edited}) |> render_change()
    view |> element("#mode-visual") |> render_click()

    assert has_element?(view, "#json-error", "Severity is invalid")
    assert has_element?(view, "#rule-json")
  end

  test "saving JSON with an invalid value explains the problem instead of crashing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")

    view |> element("#mode-json") |> render_click()

    json =
      view |> element("#rule-json") |> render() |> LazyHTML.from_fragment() |> LazyHTML.text()

    edited = json |> Jason.decode!() |> Map.put("severity", "urgent") |> Jason.encode!()
    view |> form("#json-form", %{"json" => edited}) |> render_submit()

    assert has_element?(view, "#rule-errors", "Severity is invalid")
  end

  test "invalid JSON keeps you in JSON mode with an explanation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")

    view |> element("#mode-json") |> render_click()
    view |> form("#json-form", %{"json" => "{not json"}) |> render_change()
    view |> element("#mode-visual") |> render_click()

    assert has_element?(view, "#json-error", "Invalid JSON")
    assert has_element?(view, "#rule-json")
  end

  test "edits an existing rule", %{conn: conn, team: team} do
    rule = rule_fixture(team)
    {:ok, view, _html} = live(conn, ~p"/rules/#{rule.id}")

    assert has_element?(view, "#rule-name[value='Disk full']")

    view |> form("#rule-form", %{"name" => "Disk almost full"}) |> render_change()

    assert {:error, {:live_redirect, %{to: "/rules"}}} =
             view |> form("#rule-form") |> render_submit()

    assert Repo.get!(Rule, rule.id).name == "Disk almost full"
  end

  test "Create a rule from this event preloads the alert's event for testing", %{
    conn: conn,
    team: team
  } do
    alert = team |> rule_fixture() |> alert_fixture()

    {:ok, alert_view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    assert {:error, {:live_redirect, %{to: path}}} =
             alert_view |> element("#rule-from-event") |> render_click()

    {:ok, view, _html} = live(conn, path)
    assert view |> element("#test-event") |> render() =~ "DISK_FULL"
    assert has_element?(view, "#test-result")
  end
end
