defmodule Minion.Channels.DiscordTest do
  use Minion.DataCase, async: true

  import Minion.AlertFixtures

  alias Minion.Accounts.Person
  alias Minion.Channels.Discord
  alias Minion.Runbooks

  @url "https://discord.com/api/webhooks/123456/abc-DEF_ghi"

  setup do
    team = team_fixture()

    rule =
      rule_fixture(team, %{
        severity: :critical,
        present: %{"title" => "Disk full on {{payload.host}}", "fields" => ["payload.host"]}
      })

    {:ok, _} =
      rule.id
      |> Runbooks.get_or_build_for_rule()
      |> Runbooks.save_runbook(%{body: "1. Clean /var on {{payload.host}}"})

    alert = alert_fixture(rule, %{severity: :critical, body: "@everyone web-1 is full"})
    %{alert: alert, person: %Person{name: "Anna", discord_webhook_url: @url}}
  end

  defp capture(status) do
    test_pid = self()

    Req.Test.stub(Discord, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:discord, conn.request_path, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, status, "")
    end)
  end

  test "posts an embed with severity colour, link, fields and runbook", %{
    alert: alert,
    person: person
  } do
    capture(204)

    assert Discord.deliver(alert, person) == :ok
    assert_received {:discord, "/api/webhooks/123456/abc-DEF_ghi", message}

    assert %{
             "username" => "Minion",
             "allowed_mentions" => %{"parse" => []},
             "embeds" => [embed]
           } = message

    assert embed["title"] == "[CRITICAL] Disk full on web-1"
    assert embed["color"] == 0xE5484D
    assert embed["url"] =~ "/alerts/#{alert.id}"
    assert embed["description"] == "@everyone web-1 is full"
    assert %{"name" => "host", "value" => "web-1", "inline" => true} in embed["fields"]
    assert %{"name" => "What to do", "value" => "1. Clean /var on web-1"} in embed["fields"]
  end

  test "an error status is returned so the worker retries", %{alert: alert, person: person} do
    capture(429)
    assert Discord.deliver(alert, person) == {:error, {:discord_status, 429}}
  end

  test "no webhook is a permanent error", %{alert: alert} do
    assert Discord.deliver(alert, %Person{name: "Piotr"}) == {:error, :no_discord_webhook}
    assert Minion.Channels.permanent_error?(:discord, :no_discord_webhook)
  end

  test "only Discord webhook URLs are accepted on a person" do
    valid = Person.changeset(%Person{}, %{name: "Anna", discord_webhook_url: @url})
    assert valid.valid?

    for url <- [
          "http://discord.com/api/webhooks/1/x",
          "https://evil.example/api/webhooks/1/x",
          "https://discord.com.evil.example/api/webhooks/1/x",
          "https://discord.com/api/webhooks/1/x?wait=true#"
        ] do
      refute Person.changeset(%Person{}, %{name: "Anna", discord_webhook_url: url}).valid?, url
    end
  end

  test "the webhook never shows up in inspect output" do
    refute inspect(%Person{discord_webhook_url: @url}) =~ "abc-DEF"
  end
end
