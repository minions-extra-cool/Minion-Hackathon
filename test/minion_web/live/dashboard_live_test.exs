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
    assert has_element?(view, "#home-logo #minion-logo")
    assert has_element?(view, "#nav-dashboard")
    assert has_element?(view, "#nav-rules")
  end

  test "lists alerts with their status light", %{conn: conn, rule: rule} do
    open = alert_fixture(rule, %{title: "Disk full on web-1"})
    acked = alert_fixture(rule, %{title: "Disk full on web-2", status: :acked})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#alerts-#{open.id} [data-status=open][data-severity=warning]")
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

    {:ok, _} = Minion.Alerts.acknowledge(alert.id, person_fixture(team_fixture()).id)

    assert has_element?(view, "#alerts-#{alert.id} [data-status=acked]")
  end

  describe "search" do
    setup %{rule: rule} do
      %{
        web: alert_fixture(rule, %{title: "Disk full on web-3"}),
        db: alert_fixture(rule, %{title: "Disk full on db-1"})
      }
    end

    test "typing filters the feed and puts the query in the URL", %{
      conn: conn,
      web: web,
      db: db
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#search-form", %{"q" => "web3"}) |> render_change()

      assert_patch(view, ~p"/?q=web3")
      assert has_element?(view, "#alerts-#{web.id}")
      refute has_element?(view, "#alerts-#{db.id}")
      assert has_element?(view, "#search-summary", "web3")
    end

    test "a shared link opens with the search applied, and Clear removes it", %{
      conn: conn,
      web: web,
      db: db
    } do
      {:ok, view, _html} = live(conn, ~p"/?q=db")

      assert has_element?(view, "#alerts-#{db.id}")
      refute has_element?(view, "#alerts-#{web.id}")

      view |> element("#clear-search") |> render_click()

      assert_patch(view, ~p"/")
      assert has_element?(view, "#alerts-#{web.id}")
      refute has_element?(view, "#search-summary")
    end

    test "matches source and owner as well as the title", %{conn: conn, team: team, web: web} do
      {:ok, view, _html} = live(conn, ~p"/?q=#{team.name}")
      assert has_element?(view, "#alerts-#{web.id}")

      {:ok, view, _html} = live(conn, ~p"/?q=opsmon")
      assert has_element?(view, "#alerts-#{web.id}")
    end

    test "live updates respect the search", %{conn: conn, rule: rule} do
      {:ok, view, _html} = live(conn, ~p"/?q=web")

      event =
        Minion.Ingest.envelope("ops-monitor", "http", %{
          "type" => "DISK_FULL",
          "host" => "cache-7"
        })

      {:ok, [{:created, hidden}]} = Processor.process(event, [rule], dispatch: fn _ -> :ok end)

      refute has_element?(view, "#alerts-#{hidden.id}")
    end
  end

  test "clicking an alert opens its detail page", %{conn: conn, rule: rule} do
    alert = alert_fixture(rule)
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:error, {:live_redirect, %{to: path}}} =
             view |> element("#alerts-#{alert.id} a") |> render_click()

    assert path == ~p"/alerts/#{alert.id}"
  end
end
