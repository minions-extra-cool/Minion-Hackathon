defmodule Minion.AI.SummaryTest do
  use Minion.DataCase, async: true

  import Minion.AlertFixtures

  alias Minion.AI.{Gemini, Summary}

  setup do
    team = team_fixture()

    rule =
      rule_fixture(team, %{
        present: %{
          "title" => "Disk full on {{payload.host}}",
          "fields" => ["payload.host"],
          "color" => "amber"
        }
      })

    %{rule: rule, alert: %{alert_fixture(rule) | rule: rule}}
  end

  test "the prompt carries the alert's facts and rendered fields", %{alert: alert} do
    prompt = Summary.build_prompt(alert)

    assert prompt =~ "Title: Disk full on web-1"
    assert prompt =~ "Severity: warning"
    assert prompt =~ "Status: open"
    assert prompt =~ "Rule: Disk full"
    assert prompt =~ "Fields:\n  payload.host = web-1"
    assert prompt =~ "\"host\": \"web-1\""
  end

  test "an oversized payload is truncated", %{rule: rule} do
    alert =
      alert_fixture(rule, %{
        sample_event: %{"payload" => %{"blob" => String.duplicate("x", 9_000)}}
      })

    prompt = Summary.build_prompt(alert)

    assert prompt =~ "(truncated)"
    assert byte_size(prompt) < 8_000
  end

  test "the client's answer is passed through", %{alert: alert} do
    previous = Application.get_env(:minion, :ai_stub_response)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:minion, :ai_stub_response, previous),
        else: Application.delete_env(:minion, :ai_stub_response)
    end)

    Application.put_env(:minion, :ai_stub_response, {:ok, "stub summary"})
    assert {:ok, "stub summary"} = Summary.summarize(alert, Minion.AI.StubClient)

    Application.put_env(:minion, :ai_stub_response, {:error, :boom})
    assert {:error, :boom} = Summary.summarize(alert, Minion.AI.StubClient)
  end

  test "a summary prompt travels through the Gemini request and comes back parsed", %{
    alert: alert
  } do
    Req.Test.stub(Gemini, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %{"contents" => [%{"parts" => [%{"text" => prompt}]}]} = Jason.decode!(body)
      assert prompt =~ "Title: Disk full on web-1"

      Req.Test.json(conn, %{
        "candidates" => [%{"content" => %{"parts" => [%{"text" => "disk cleanup needed"}]}}]
      })
    end)

    assert {:ok, "disk cleanup needed"} = Summary.summarize(alert, Gemini)
  end
end
