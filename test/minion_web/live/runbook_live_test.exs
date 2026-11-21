defmodule MinionWeb.RunbookLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Runbooks

  setup do
    rule = rule_fixture(team_fixture())
    %{rule: rule, alert: alert_fixture(rule)}
  end

  test "writing a runbook from an alert previews it and returns to the alert", %{
    conn: conn,
    rule: rule,
    alert: alert
  } do
    {:ok, view, _html} = live(conn, ~p"/rules/#{rule.id}/runbook?#{[from_alert: alert.id]}")

    assert has_element?(view, "#runbook-rule-name", rule.name)

    view
    |> form("#runbook-form", runbook: %{body: "Free space on {{payload.host}}"})
    |> render_change()

    assert has_element?(view, "#runbook-preview", "Free space on web-1")

    {:ok, _alert_view, html} =
      view
      |> form("#runbook-form", runbook: %{body: "Free space on {{payload.host}}"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/alerts/#{alert.id}")

    assert html =~ "Runbook saved."
    assert Runbooks.get_for_rule(rule.id).body == "Free space on {{payload.host}}"
  end

  test "without an alert it previews the raw text and returns to the rule", %{
    conn: conn,
    rule: rule
  } do
    {:ok, _} = Runbooks.save_runbook(%Runbooks.Runbook{rule_id: rule.id}, %{body: "Old"})
    {:ok, view, _html} = live(conn, ~p"/rules/#{rule.id}/runbook")

    assert has_element?(view, "#runbook-updated-at")

    view
    |> form("#runbook-form", runbook: %{body: "Check {{payload.host}}"})
    |> render_change()

    assert has_element?(view, "#runbook-preview", "Check {{payload.host}}")

    view
    |> form("#runbook-form", runbook: %{body: "New"})
    |> render_submit()

    assert_redirect(view, ~p"/rules/#{rule.id}")
    assert Runbooks.get_for_rule(rule.id).body == "New"
  end

  test "an alert from another rule is ignored", %{conn: conn, rule: rule} do
    other_alert = alert_fixture(rule_fixture(team_fixture()))
    {:ok, view, _html} = live(conn, ~p"/rules/#{rule.id}/runbook?#{[from_alert: other_alert.id]}")

    assert has_element?(view, "#runbook-back[href='/rules/#{rule.id}']")
  end
end
