defmodule MinionWeb.PersonLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Accounts
  alias MinionWeb.PersonLive

  setup %{conn: conn} do
    team = team_fixture()
    anna = person_fixture(team, "Anna")

    {:ok, anna} =
      Accounts.update_person(anna, %{
        preferences: %{
          "critical" => [
            %{"channels" => ["sms"], "hours" => [8, 20]},
            %{"channels" => ["email"]}
          ],
          "warning" => [%{"channels" => ["email"]}],
          "info" => []
        }
      })

    %{conn: Plug.Test.init_test_session(conn, %{"person_id" => anna.id}), anna: anna, team: team}
  end

  test "the menu links to your own profile", %{conn: conn, anna: anna} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#my-profile[href='/people/#{anna.id}']")
  end

  test "shows the preferences in plain words", %{conn: conn, anna: anna} do
    {:ok, view, _html} = live(conn, ~p"/people/#{anna.id}")

    assert has_element?(view, "#this-is-you")

    assert has_element?(
             view,
             "#prefs-critical-summary",
             "SMS from 08:00 to 20:00 UTC, otherwise Email"
           )

    assert has_element?(view, "#prefs-info-summary", "Shown in the feed only")
  end

  test "adding, editing, reordering and saving preferences", %{conn: conn, anna: anna} do
    {:ok, view, _html} = live(conn, ~p"/people/#{anna.id}")

    view |> element("#prefs-info-add") |> render_click()
    assert has_element?(view, "#prefs-info-0")

    view
    |> form("#person-form", %{
      "prefs" => %{
        "critical" => %{
          "0" => %{"channels" => ["", "sms"], "limited" => "true", "from" => "8", "to" => "20"},
          "1" => %{"channels" => ["", "email", "phone"], "limited" => "false"}
        },
        "warning" => %{"0" => %{"channels" => ["", "email"], "limited" => "false"}},
        "info" => %{"0" => %{"channels" => ["", "email"], "limited" => "true"}}
      }
    })
    |> render_change()

    assert has_element?(
             view,
             "#prefs-info-summary",
             "Email from 08:00 to 20:00 UTC, otherwise feed only"
           )

    view |> element("#prefs-critical-1-up") |> render_click()

    assert has_element?(
             view,
             "#prefs-critical-summary",
             "Email + Phone call, otherwise SMS from 08:00 to 20:00 UTC"
           )

    view
    |> form("#person-form", %{"person" => %{"phone" => "+48 111 222 333"}})
    |> render_submit()

    saved = Accounts.get_person!(anna.id)
    assert saved.phone == "+48 111 222 333"

    assert saved.preferences == %{
             "critical" => [
               %{"channels" => ["email", "phone"]},
               %{"channels" => ["sms"], "hours" => [8, 20]}
             ],
             "warning" => [%{"channels" => ["email"]}],
             "info" => [%{"channels" => ["email"], "hours" => [8, 20]}]
           }
  end

  test "removing every line makes a severity feed-only", %{conn: conn, anna: anna} do
    {:ok, view, _html} = live(conn, ~p"/people/#{anna.id}")

    view |> element("#prefs-warning-0-remove") |> render_click()
    assert has_element?(view, "#prefs-warning-summary", "Shown in the feed only")

    view |> form("#person-form") |> render_submit()
    assert Accounts.get_person!(anna.id).preferences["warning"] == []
  end

  describe "Discord webhook" do
    @webhook "https://discord.com/api/webhooks/42/secret-token"

    test "is saved, never sent back to the browser, kept on a blank save and removable", %{
      conn: conn,
      anna: anna
    } do
      {:ok, view, _html} = live(conn, ~p"/people/#{anna.id}")
      assert has_element?(view, "#prefs-critical-0 input[value=discord]")

      html =
        view
        |> form("#person-form", %{"person" => %{"discord_webhook_url" => @webhook}})
        |> render_submit()

      assert Accounts.get_person!(anna.id).discord_webhook_url == @webhook
      assert has_element?(view, "#discord-saved")
      refute html =~ "secret-token"

      {:ok, view, html} = live(conn, ~p"/people/#{anna.id}")
      refute html =~ "secret-token"

      view
      |> form("#person-form", %{
        "person" => %{"discord_webhook_url" => "", "phone" => "+48 1 2 3 4 5"}
      })
      |> render_submit()

      assert Accounts.get_person!(anna.id).discord_webhook_url == @webhook

      view |> element("#remove-discord") |> render_click()
      assert Accounts.get_person!(anna.id).discord_webhook_url == nil
      refute has_element?(view, "#discord-saved")
    end

    test "rejects a URL that is not a Discord webhook", %{conn: conn, anna: anna} do
      {:ok, view, _html} = live(conn, ~p"/people/#{anna.id}")

      html =
        view
        |> form("#person-form", %{
          "person" => %{"discord_webhook_url" => "https://evil.example/hook"}
        })
        |> render_submit()

      assert html =~ "must be a Discord webhook URL"
      assert Accounts.get_person!(anna.id).discord_webhook_url == nil
    end
  end

  test "invalid contact details are shown and not saved", %{conn: conn, anna: anna} do
    {:ok, view, _html} = live(conn, ~p"/people/#{anna.id}")

    html =
      view |> form("#person-form", %{"person" => %{"email" => "nope"}}) |> render_submit()

    assert html =~ "must look like name@example.com"
    assert Accounts.get_person!(anna.id).email == "anna@minion.test"
  end

  test "preferences saved here drive real deliveries", %{conn: conn, anna: anna, team: team} do
    {:ok, view, _html} = live(conn, ~p"/people/#{anna.id}")
    view |> form("#person-form") |> render_submit()

    rule =
      rule_fixture(team, %{severity: :critical, notify: [%{"type" => "person", "id" => anna.id}]})

    day = alert_fixture(rule, %{severity: :critical})
    night = alert_fixture(rule, %{severity: :critical})

    Minion.Delivery.dispatch(day, ~U[2026-11-20 10:00:00Z])
    Minion.Delivery.dispatch(night, ~U[2026-11-20 23:00:00Z])

    assert channels_for(day) == [:sms]
    assert channels_for(night) == [:email]
  end

  test "an empty severity reads as feed only" do
    assert PersonLive.describe([]) =~ "feed only"
  end

  defp channels_for(alert),
    do: alert |> Minion.Alerts.list_deliveries() |> Enum.map(& &1.channel)
end
