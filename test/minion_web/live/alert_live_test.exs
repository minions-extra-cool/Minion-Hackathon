defmodule MinionWeb.AlertLiveTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Alerts

  setup do
    previous_client = Application.get_env(:minion, :ai_client)

    on_exit(fn ->
      if previous_client,
        do: Application.put_env(:minion, :ai_client, previous_client),
        else: Application.delete_env(:minion, :ai_client)
    end)

    Application.put_env(:minion, :ai_client, Minion.AI.StubClient)

    team = team_fixture()

    rule =
      rule_fixture(team, %{
        present: %{
          "title" => "Disk full on {{payload.host}}",
          "fields" => ["payload.host", "payload.missing"],
          "color" => "red"
        }
      })

    %{team: team, rule: rule, alert: alert_fixture(rule), anna: person_fixture(team, "Anna")}
  end

  defp act_as(view, person) do
    view |> form("#acting-as-form", %{person_id: person.id}) |> render_change()
    view
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

  test "acknowledging and resolving wait until you say who you are", %{conn: conn, alert: alert} do
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    assert has_element?(view, "#acknowledge[disabled]")
    assert has_element?(view, "#resolve[disabled]")
    assert render_hook(view, "acknowledge", %{}) =~ "Pick who you are first."
    assert has_element?(view, "#alert-status[data-status=open]")
  end

  test "acknowledging then resolving records who did it", %{
    conn: conn,
    alert: alert,
    anna: anna
  } do
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")
    act_as(view, anna)

    view |> element("#acknowledge") |> render_click()
    assert has_element?(view, "#alert-status[data-status=acked]")
    assert has_element?(view, "#alert-acked-by", "by Anna")
    refute has_element?(view, "#acknowledge")

    view |> element("#resolve") |> render_click()
    assert has_element?(view, "#resolve-confirm-dialog")

    view |> element("#resolve-confirm") |> render_click()
    assert has_element?(view, "#alert-status[data-status=resolved]")
    assert has_element?(view, "#alert-resolved-by", "by Anna")
    refute has_element?(view, "#resolve")
    assert Alerts.get_alert(alert.id).resolved_by_id == anna.id
  end

  test "the resolution note is saved and shown", %{conn: conn, alert: alert, anna: anna} do
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")
    act_as(view, anna)

    view |> element("#resolve") |> render_click()
    view |> element("#resolve-confirm") |> render_click()

    view
    |> form("#resolve-runbook-prompt", %{note: "Cleared /var/log on web-1"})
    |> render_submit(%{next: "close"})

    refute has_element?(view, "#resolve-confirm-dialog")
    assert has_element?(view, "#alert-resolution-note", "Cleared /var/log on web-1")
    assert Alerts.get_alert(alert.id).resolution_note == "Cleared /var/log on web-1"
  end

  test "an alert resolved by the quiet sweep says it was automatic", %{conn: conn, alert: alert} do
    Minion.Repo.update_all(Minion.Alerts.Alert,
      set: [status: :resolved, resolved_at: DateTime.utc_now()]
    )

    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    assert has_element?(view, "#alert-resolved-by", "automatically")
  end

  test "resolving asks for confirmation and can be cancelled", %{
    conn: conn,
    alert: alert,
    anna: anna
  } do
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")
    act_as(view, anna)

    view |> element("#resolve") |> render_click()
    assert has_element?(view, "#resolve-confirm-dialog")

    view |> element("#resolve-cancel") |> render_click()
    refute has_element?(view, "#resolve-confirm-dialog")
    assert has_element?(view, "#alert-status[data-status=open]")

    view |> element("#resolve") |> render_click()
    view |> element("#resolve-confirm") |> render_click()
    assert has_element?(view, "#alert-status[data-status=resolved]")
  end

  test "a status change made elsewhere shows up live", %{conn: conn, alert: alert, anna: anna} do
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    {:ok, _} = Alerts.resolve(alert.id, anna.id)

    assert has_element?(view, "#alert-status[data-status=resolved]")
    assert has_element?(view, "#alert-resolved-by", "by Anna")
  end

  test "acting on an alert someone already resolved explains what happened", %{
    conn: conn,
    alert: alert,
    anna: anna
  } do
    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")
    act_as(view, anna)
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

  describe "runbooks" do
    test "an unresolved alert shows its runbook filled in from the event", %{
      conn: conn,
      rule: rule,
      alert: alert
    } do
      {:ok, _} =
        Minion.Runbooks.save_runbook(%Minion.Runbooks.Runbook{rule_id: rule.id}, %{
          body: "1. Clear /var/log on **{{payload.host}}**"
        })

      {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

      assert has_element?(view, "#runbook-body ol li strong", "web-1")
      assert has_element?(view, "#runbook-body li", "Clear /var/log on")
      assert has_element?(view, "#runbook-edit", "Edit runbook")
    end

    test "expanding the runbook opens it in a dialog that can be closed", %{
      conn: conn,
      rule: rule,
      alert: alert
    } do
      {:ok, _} =
        Minion.Runbooks.save_runbook(%Minion.Runbooks.Runbook{rule_id: rule.id}, %{
          body: "- check {{payload.host}}"
        })

      {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")
      refute has_element?(view, "#runbook-dialog")

      view |> element("#runbook-expand") |> render_click()
      assert has_element?(view, "#runbook-dialog-body li", "check web-1")
      assert has_element?(view, "#runbook-dialog-edit", "Edit runbook")

      view |> element("#runbook-dialog-close") |> render_click()
      refute has_element?(view, "#runbook-dialog")
    end

    test "an alert without a runbook invites writing one", %{conn: conn, rule: rule, alert: alert} do
      {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

      assert has_element?(view, "#runbook-missing")

      assert has_element?(
               view,
               "#runbook-edit[href='/rules/#{rule.id}/runbook?from_alert=#{alert.id}']",
               "Write a runbook"
             )
    end

    test "resolving asks to update the runbook and links to the editor", %{
      conn: conn,
      rule: rule,
      alert: alert,
      anna: anna
    } do
      {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")
      act_as(view, anna)

      view |> element("#resolve") |> render_click()
      view |> element("#resolve-confirm") |> render_click()

      assert has_element?(view, "#resolve-done-title", "Alert resolved")
      assert has_element?(view, "#resolve-runbook-prompt", "write a runbook")
      refute has_element?(view, "#runbook")

      {:ok, _editor, html} =
        view
        |> form("#resolve-runbook-prompt", %{note: "Rotated logs"})
        |> render_submit(%{next: "runbook"})
        |> follow_redirect(conn, ~p"/rules/#{rule.id}/runbook?#{[from_alert: alert.id]}")

      assert html =~ "runbook-form"
      assert Alerts.get_alert(alert.id).resolution_note == "Rotated logs"
    end

    test "choosing done closes the dialog and keeps a link to the runbook", %{
      conn: conn,
      alert: alert,
      anna: anna
    } do
      {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")
      act_as(view, anna)

      view |> element("#resolve") |> render_click()
      view |> element("#resolve-confirm") |> render_click()
      view |> form("#resolve-runbook-prompt") |> render_submit(%{next: "close"})

      refute has_element?(view, "#resolve-confirm-dialog")
      assert has_element?(view, "#runbook-edit")
      assert Alerts.get_alert(alert.id).resolution_note == nil
    end

    test "an alert whose rule was deleted resolves without the runbook prompt", %{
      conn: conn,
      rule: rule,
      anna: anna
    } do
      alert = alert_fixture(rule, %{rule_id: nil})
      {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")
      act_as(view, anna)

      view |> element("#resolve") |> render_click()
      view |> element("#resolve-confirm") |> render_click()

      assert has_element?(view, "#resolve-done", "Done")
      refute has_element?(view, "#resolve-update-runbook")
    end
  end

  test "summarizing renders markdown in the AI summary", %{conn: conn, alert: alert} do
    previous = Application.get_env(:minion, :ai_stub_response)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:minion, :ai_stub_response, previous),
        else: Application.delete_env(:minion, :ai_stub_response)
    end)

    Application.put_env(
      :minion,
      :ai_stub_response,
      {:ok, "## What happened\n\nDisk on **web-1** is nearly full.\n\n- run `df -h`\n- restart"}
    )

    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")

    html = view |> element("#summarize-alert") |> render_click()
    assert html =~ "Summarising"

    assert render_async(view) =~ "What happened"
    assert has_element?(view, "#ai-summary-text h2", "What happened")
    assert has_element?(view, "#ai-summary-text strong", "web-1")
    assert has_element?(view, "#ai-summary-text code", "df -h")
    assert has_element?(view, "#ai-summary-text li", "restart")
    assert has_element?(view, "#summarize-alert", "Regenerate summary")
  end

  test "a failing Gemini call explains itself", %{conn: conn, alert: alert} do
    previous = Application.get_env(:minion, :ai_stub_response)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:minion, :ai_stub_response, previous),
        else: Application.delete_env(:minion, :ai_stub_response)
    end)

    Application.put_env(:minion, :ai_stub_response, {:error, {:api_error, 429, "quota exceeded"}})

    {:ok, view, _html} = live(conn, ~p"/alerts/#{alert.id}")
    view |> element("#summarize-alert") |> render_click()

    assert render_async(view) =~ "Gemini answered 429"
    assert has_element?(view, "#ai-summary-error", "Gemini answered 429: quota exceeded")
    refute has_element?(view, "#ai-summary-text")
  end
end
