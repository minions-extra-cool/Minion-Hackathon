defmodule MinionWeb.DashboardLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Alerts.Processor

  setup do
    team = team_fixture()
    %{team: team, rule: rule_fixture(team)}
  end

  test "shows an empty state when there are no alerts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#alerts-empty")
    assert has_element?(view, "#live-indicator[data-live=true]")
    assert has_element?(view, "#nav-dashboard")
    assert has_element?(view, "#nav-rules")
  end

  test "lists alerts with their status light", %{conn: conn, rule: rule} do
    open = alert_fixture(rule, %{title: "Disk full on web-1"})
    acked = alert_fixture(rule, %{title: "Disk full on web-2", status: :acked})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#alerts-#{open.id} [data-status=open]")
    assert has_element?(view, "#alerts-#{acked.id} [data-status=acked]")
    assert has_element?(view, "#alerts-#{open.id} a", "Disk full on web-1")
  end

  test "new alerts and counter changes appear without a refresh", %{conn: conn, rule: rule} do
    {:ok, view, _html} = live(conn, ~p"/")

    event =
      Minion.Ingest.envelope("ops-monitor", "http", %{"type" => "DISK_FULL", "host" => "db-9"})

    {:ok, [{:created, alert}]} = Processor.process(event, [rule], dispatch: fn _ -> :ok end)
    assert has_element?(view, "#alerts-#{alert.id} a", "Disk full on db-9")
    assert view |> element("#alerts-#{alert.id}-count") |> render() =~ ~r/>\s*1\s*</

    {:ok, [{:updated, _}]} = Processor.process(event, [rule], dispatch: fn _ -> :ok end)
    assert view |> element("#alerts-#{alert.id}-count") |> render() =~ ~r/>\s*2\s*</
  end

  test "an acknowledgement elsewhere turns the light amber", %{conn: conn, rule: rule} do
    alert = alert_fixture(rule)
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, _} = Minion.Alerts.acknowledge(alert.id)

    assert has_element?(view, "#alerts-#{alert.id} [data-status=acked]")
  end

  test "clicking an alert opens its detail page", %{conn: conn, rule: rule} do
    alert = alert_fixture(rule)
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:error, {:live_redirect, %{to: path}}} =
             view |> element("#alerts-#{alert.id} a") |> render_click()

    assert path == ~p"/alerts/#{alert.id}"
  end
end
