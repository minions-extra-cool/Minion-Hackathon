defmodule MinionWeb.DashboardLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Alerts.Processor

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
    test "shows alerts of your team's rules and your own rules, not other teams'", %{
      conn: conn,
      rule: rule,
      person: person
    } do
      mine = alert_fixture(rule, %{title: "Team alert"})
      own_rule = rule_fixture(team_fixture(), %{owner_type: :person, owner_id: person.id})
      personal = alert_fixture(own_rule, %{title: "Personal alert"})
      other = alert_fixture(rule_fixture(team_fixture()), %{title: "Someone else's"})

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#alerts-#{mine.id}")
      assert has_element?(view, "#alerts-#{personal.id}")
      refute has_element?(view, "#alerts-#{other.id}")
    end

    test "other teams' alerts do not show up live, and search cannot find them", %{conn: conn} do
      other_rule = rule_fixture(team_fixture())
      {:ok, view, _html} = live(conn, ~p"/")

      event =
        Minion.Ingest.envelope("ops-monitor", "http", %{"type" => "DISK_FULL", "host" => "x-1"})

      {:ok, [{:created, hidden}]} =
        Processor.process(event, [other_rule], dispatch: fn _ -> :ok end)

      refute has_element?(view, "#alerts-#{hidden.id}")

      {:ok, view, _html} = live(conn, ~p"/?q=x-1")
      refute has_element?(view, "#alerts-#{hidden.id}")
    end

    test "nobody picked sees no alerts and is asked to pick", %{rule: rule} do
      alert = alert_fixture(rule)

      {:ok, view, _html} = live(build_conn(), ~p"/")

      refute has_element?(view, "#alerts-#{alert.id}")
      assert has_element?(view, "#alerts-empty", "Pick who you are")
    end
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

  test "each row shows its rule's colour next to the title", %{
    conn: conn,
    team: team,
    rule: rule
  } do
    coloured = alert_fixture(rule)
    plain_rule = rule_fixture(team, %{present: %{"title" => "Plain"}})
    plain = alert_fixture(plain_rule)

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "#alerts-#{coloured.id}-color[data-color=amber]",
             "Rule colour: amber"
           )

    refute has_element?(view, "#alerts-#{plain.id}-color")
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

  defp row_order(view) do
    ~r/id="alerts-([0-9a-f-]{36})"/
    |> Regex.scan(view |> element("#alerts") |> render())
    |> Enum.map(fn [_, id] -> id end)
  end

  describe "sorting" do
    setup %{rule: rule} do
      %{
        busy:
          alert_fixture(rule, %{
            title: "Busy",
            count: 40,
            last_seen: ~U[2026-11-21 08:00:00.000000Z]
          }),
        quiet:
          alert_fixture(rule, %{
            title: "quiet",
            count: 2,
            last_seen: ~U[2026-11-21 09:00:00.000000Z]
          }),
        middle:
          alert_fixture(rule, %{
            title: "Middle",
            count: 9,
            last_seen: ~U[2026-11-21 10:00:00.000000Z]
          })
      }
    end

    test "is newest first until a header is clicked", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      assert row_order(view) == [ctx.middle.id, ctx.quiet.id, ctx.busy.id]
      assert has_element?(view, "#column-last_seen[aria-sort=descending]")
    end

    test "clicking a header sorts by it and clicking again flips it, in the URL",
         %{
           conn: conn
         } = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#sort-title") |> render_click()
      assert_patch(view, ~p"/?#{[sort: "title", dir: "asc"]}")
      assert row_order(view) == [ctx.busy.id, ctx.middle.id, ctx.quiet.id]
      assert has_element?(view, "#column-title[aria-sort=ascending]")

      view |> element("#sort-title") |> render_click()
      assert_patch(view, ~p"/?#{[sort: "title", dir: "desc"]}")
      assert row_order(view) == [ctx.quiet.id, ctx.middle.id, ctx.busy.id]
    end

    test "a shared link opens sorted, and search keeps the sort", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?#{[sort: "count", dir: "desc"]}")
      assert row_order(view) == [ctx.busy.id, ctx.middle.id, ctx.quiet.id]

      view |> form("#search-form", %{q: "i"}) |> render_change()
      assert_patch(view, ~p"/?#{[q: "i", sort: "count", dir: "desc"]}")
    end

    test "a live update moves the row to its sorted place", %{conn: conn, rule: rule} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?#{[sort: "count", dir: "desc"]}")

      updated = %{ctx.quiet | count: 100, rule: rule}

      Phoenix.PubSub.broadcast(
        Minion.PubSub,
        Minion.Alerts.topic(updated),
        {:alert, :updated, updated}
      )

      assert row_order(view) == [ctx.quiet.id, ctx.busy.id, ctx.middle.id]
      assert view |> element("#alerts-#{ctx.quiet.id}-count") |> render() =~ "100"
    end
  end

  describe "columns" do
    test "can be shown, moved, hidden and reset, and each change is saved", %{
      conn: conn,
      rule: rule
    } do
      alert = alert_fixture(rule)
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#column-rule")
      view |> element("#columns-hidden-rule input") |> render_click()
      assert has_element?(view, "#column-rule")
      assert has_element?(view, "#alerts-#{alert.id} td", rule.name)

      assert_push_event(view, "columns_saved", %{
        columns: ["title", "source", "owner", "count", "last_seen", "rule"]
      })

      view |> element("#move-rule-up") |> render_click()

      assert_push_event(view, "columns_saved", %{
        columns: ["title", "source", "owner", "count", "rule", "last_seen"]
      })

      view |> element("#columns-shown-source input") |> render_click()
      refute has_element?(view, "#column-source")

      view |> element("#reset-columns") |> render_click()
      assert has_element?(view, "#column-source")
      refute has_element?(view, "#column-rule")
    end

    test "the title cannot be hidden", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#columns-shown-title input[disabled]")
    end

    test "a layout saved in the browser is restored, ignoring junk", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "set_columns", %{"columns" => ["count", "bogus", "first_seen"]})

      assert has_element?(view, "#column-first_seen")
      refute has_element?(view, "#column-owner")
      assert has_element?(view, "#column-title")
    end
  end
end
