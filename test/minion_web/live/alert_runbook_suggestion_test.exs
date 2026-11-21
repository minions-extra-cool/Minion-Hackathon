defmodule MinionWeb.AlertRunbookSuggestionTest do
  use MinionWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Runbooks

  setup %{conn: conn} do
    previous = Application.get_env(:minion, :ai_stub_response)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:minion, :ai_stub_response, previous),
        else: Application.delete_env(:minion, :ai_stub_response)
    end)

    team = team_fixture()
    anna = person_fixture(team, "Anna")
    rule = rule_fixture(team)

    {:ok, _} =
      rule.id
      |> Runbooks.get_or_build_for_rule()
      |> Runbooks.save_runbook(%{body: "1. Check disk usage on {{payload.host}}"})

    %{
      conn: Plug.Test.init_test_session(conn, %{"person_id" => anna.id}),
      rule: rule,
      alert: alert_fixture(rule)
    }
  end

  defp resolve_with_note(view, note) do
    view |> element("#resolve") |> render_click()
    view |> element("#resolve-confirm") |> render_click()
    view |> form("#resolve-note-form", %{note: note}) |> render_submit(%{next: "save"})
  end

  test "the note becomes a suggested runbook that can be edited and saved", %{
    conn: conn,
    rule: rule,
    alert: alert
  } do
    suggestion =
      "1. Check disk usage on {{payload.host}}\n2. Rotate /var/log on {{payload.host}}"

    Application.put_env(:minion, :ai_stub_response, {:ok, "```\n#{suggestion}\n```"})
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    resolve_with_note(view, "Rotated /var/log on web-1")

    assert has_element?(view, "#resolve-runbook-title", "Update the runbook?")
    render_async(view)

    assert view |> element("#runbook-suggestion") |> render() =~
             "Rotate /var/log on {{payload.host}}"

    view
    |> form("#runbook-suggestion-form", %{body: suggestion <> "\n3. Tell #ops"})
    |> render_submit()

    refute has_element?(view, "#resolve-confirm-dialog")
    assert Runbooks.get_for_rule(rule.id).body == suggestion <> "\n3. Tell #ops"
  end

  test "if the AI fails, the person can still open the runbook editor", %{
    conn: conn,
    rule: rule,
    alert: alert
  } do
    Application.put_env(:minion, :ai_stub_response, {:error, :not_configured})
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    resolve_with_note(view, "Rotated logs")
    render_async(view)

    assert has_element?(view, "#runbook-suggestion-error")
    assert has_element?(view, "#resolve-update-runbook", "Update runbook")
    assert Runbooks.get_for_rule(rule.id).body == "1. Check disk usage on {{payload.host}}"
  end
end
