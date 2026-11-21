defmodule MinionWeb.UnmatchedLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Unmatched

  defp event(source, payload), do: Minion.Ingest.envelope(source, "http", payload)

  test "the feed has Alerts and Unmatched events tabs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#tab-alerts")

    assert {:error, {:live_redirect, %{to: "/unmatched"}}} =
             view |> element("#tab-unmatched") |> render_click()
  end

  test "lists unmatched shapes and adds new ones live", %{conn: conn} do
    shape = Unmatched.record(event("ops-monitor", %{"type" => "CPU_HIGH", "host" => "web-1"}))
    {:ok, view, _html} = live(conn, ~p"/unmatched")

    assert has_element?(view, "#shapes-#{shape.id}", "ops-monitor")
    assert has_element?(view, "#shapes-#{shape.id}", "CPU_HIGH")

    Unmatched.record(event("ops-monitor", %{"type" => "CPU_HIGH", "host" => "web-2"}))
    assert view |> element("#shapes-#{shape.id}-count") |> render() =~ ~r/>\s*2\s*</

    other = Unmatched.record(event("billing", %{"kind" => "invoice.failed"}))
    assert has_element?(view, "#shapes-#{other.id}", "invoice.failed")
  end

  test "dismiss removes a shape", %{conn: conn} do
    shape = Unmatched.record(event("ops-monitor", %{"type" => "CPU_HIGH"}))
    {:ok, view, _html} = live(conn, ~p"/unmatched")

    view |> element("#shapes-#{shape.id}-dismiss") |> render_click()

    refute has_element?(view, "#shapes-#{shape.id}")
  end

  test "Create rule opens the editor with a suggested rule and the event to test", %{conn: conn} do
    team_fixture()
    shape = Unmatched.record(event("ops-monitor", %{"type" => "CPU_HIGH", "host" => "web-1"}))
    {:ok, view, _html} = live(conn, ~p"/unmatched")

    assert {:error, {:live_redirect, %{to: path}}} =
             view |> element("#shapes-#{shape.id}-create-rule") |> render_click()

    {:ok, editor, _html} = live(conn, path)

    assert has_element?(editor, "#rule-name[value='CPU_HIGH from ops-monitor']")
    assert has_element?(editor, "#condition-0 input[value='source']")
    assert has_element?(editor, "#condition-1 input[value='payload.type']")
    assert has_element?(editor, "#test-result[data-matches=true]")
  end
end
