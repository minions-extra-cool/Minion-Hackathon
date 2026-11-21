defmodule Minion.Channels.EmailTest do
  use Minion.DataCase, async: true

  import Minion.AlertFixtures
  import Swoosh.TestAssertions

  alias Minion.Channels.Email
  alias Minion.Runbooks

  setup do
    team = team_fixture()
    rule = rule_fixture(team)
    %{rule: rule, alert: alert_fixture(rule), person: person_fixture(team)}
  end

  test "the email links to the alert", %{alert: alert, person: person} do
    assert Email.deliver(alert, person) == :ok

    alert_url = MinionWeb.Links.alert_url(alert)
    assert alert_url =~ ~r"^http://\S+/alerts/#{alert.id}$"

    assert_email_sent(subject: "[WARNING] Disk full on web-1", to: "anna@minion.test")

    email = Email.build_email(alert, person)
    assert email.text_body =~ "Open the alert: #{alert_url}"
    assert email.html_body =~ ~s(href="#{alert_url}")
    refute email.text_body =~ "What to do"
  end

  test "the email carries the rule's runbook filled in from the event", %{
    rule: rule,
    alert: alert,
    person: person
  } do
    {:ok, _} =
      rule.id
      |> Runbooks.get_or_build_for_rule()
      |> Runbooks.save_runbook(%{body: "1. Clean **/var** on {{payload.host}}"})

    email = Email.build_email(alert, person)

    assert email.text_body =~ "What to do:\n1. Clean **/var** on web-1"
    assert email.html_body =~ "<h3>What to do</h3>"
    assert email.html_body =~ "<strong>/var</strong> on web-1"
  end
end
