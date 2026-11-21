defmodule MinionWeb.AlertLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Alerts

  setup do
    team = team_fixture()

    rule =
      rule_fixture(team, %{
        present: %{
          "title" => "Disk full on {{payload.host}}",
          "fields" => ["payload.host", "payload.missing"],
          "color" => "red"
        }
      })

    %{team: team, rule: rule, alert: alert_fixture(rule)}
  end

  test "shows the alert's facts", %{conn: conn, alert: alert, team: team} do
    {:ok, view, html} = live(conn, ~p"/alerts/#{alert.id}")

    assert has_element?(view, "#alert-title", "Disk full on web-1")
    assert has_element?(view, "#alert-status[data-status=open]")
    assert has_element?(view, "#alert-body", "web-1 reported a full disk.")
    assert has_element?(view, "#alert-count", "1")
    assert has_element?(view, "#alert-sample-event")
    assert has_element?(view, "#deliveries-empty")
    assert html =~ team.name
    assert html =~ "ops-monitor"
    assert html =~ "payload.host"
  end

  test "acknowledging then resolving updates the status", %{conn: conn, alert: alert} do
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    view |> element("#acknowledge") |> render_click()
    assert has_element?(view, "#alert-status[data-status=acked]")
    refute has_element?(view, "#acknowledge")

    view |> element("#resolve") |> render_click()
    assert has_element?(view, "#resolve-confirm-dialog")

    view |> element("#resolve-confirm") |> render_click()
    assert has_element?(view, "#alert-status[data-status=resolved]")
    refute has_element?(view, "#resolve")
  end

  test "resolving asks for confirmation and can be cancelled", %{conn: conn, alert: alert} do
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    view |> element("#resolve") |> render_click()
    assert has_element?(view, "#resolve-confirm-dialog")

    view |> element("#resolve-cancel") |> render_click()
    refute has_element?(view, "#resolve-confirm-dialog")
    assert has_element?(view, "#alert-status[data-status=open]")

    view |> element("#resolve") |> render_click()
    view |> element("#resolve-confirm") |> render_click()
    assert has_element?(view, "#alert-status[data-status=resolved]")
  end

  test "a status change made elsewhere shows up live", %{conn: conn, alert: alert} do
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    {:ok, _} = Alerts.resolve(alert.id)

    assert has_element?(view, "#alert-status[data-status=resolved]")
  end

  test "acting on an alert someone already resolved explains what happened", %{
    conn: conn,
    alert: alert
  } do
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")
    Minion.Repo.update_all(Minion.Alerts.Alert, set: [status: :resolved])

    view |> element("#resolve") |> render_click()
    html = view |> element("#resolve-confirm") |> render_click()

    assert html =~ "already resolved"
    assert has_element?(view, "#alert-status[data-status=resolved]")
  end

  test "delivery updates appear live", %{conn: conn, alert: alert, team: team} do
    anna = person_fixture(team, "Anna")
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    delivery = delivery_fixture(alert, anna, %{status: :delivered, attempts: 1})
    Phoenix.PubSub.broadcast(Minion.PubSub, Alerts.topic(alert), {:delivery, delivery})

    assert has_element?(view, "#deliveries-#{delivery.id}", "Anna")
    assert has_element?(view, "#deliveries-#{delivery.id}", "delivered")
  end

  test "an unknown alert is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> live(conn, ~p"/alerts/#{Ecto.UUID.generate()}") end
  end
end
