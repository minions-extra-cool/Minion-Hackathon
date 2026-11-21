defmodule MinionWeb.RuleEditorAIDraftTest do
  use MinionWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  alias Minion.Repo
  alias Minion.Rules.Rule
  alias Minion.Unmatched

  setup do
    previous = Application.get_env(:minion, :ai_stub_response)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:minion, :ai_stub_response, previous),
        else: Application.delete_env(:minion, :ai_stub_response)
    end)

    team = team_fixture()

    shape =
      Unmatched.record(
        Minion.Ingest.envelope("pricing", "http", %{
          "alertname" => "PricingLatency",
          "labels" => %{"instance" => "pricing-engine-3"},
          "latency_ms" => 1400
        })
      )

    %{team: team, shape: shape}
  end

  defp answer(team, overrides \\ %{}) do
    rule =
      Map.merge(
        %{
          "name" => "Pricing latency",
          "severity" => "warning",
          "conditions" => %{
            "all" => [
              %{"field" => "source", "op" => "eq", "value" => "pricing"},
              %{"field" => "payload.alertname", "op" => "eq", "value" => "PricingLatency"}
            ]
          },
          "dedup" => %{"key" => ["payload.labels.instance"], "quiet_sec" => 300},
          "present" => %{
            "title" => "Pricing slow on {{payload.labels.instance}}",
            "body" => "Latency {{payload.latency_ms}} ms",
            "fields" => ["payload.latency_ms"],
            "color" => "amber"
          },
          "notify" => [%{"type" => "team", "id" => team.id}]
        },
        overrides
      )

    Application.put_env(:minion, :ai_stub_response, {:ok, Jason.encode!(rule)})
  end

  test "from an unmatched event, AI drafts the whole rule and it can be saved", %{
    conn: conn,
    team: team,
    shape: shape
  } do
    answer(team)
    {:ok, view, _html} = live(conn, ~p"/rules/new?#{[from_unmatched: shape.id]}")

    assert has_element?(view, "#ai-draft-status", "AI can draft this whole rule")

    view |> element("#ai-draft-button") |> render_click()
    render_async(view)

    assert has_element?(view, "#ai-draft-status", "it matches that event")
    assert has_element?(view, "#ai-draft-button", "Draft again")

    view |> form("#rule-form") |> render_submit()

    rule = Repo.get_by!(Rule, name: "Pricing latency")
    assert rule.severity == :warning
    assert rule.dedup == %{"key" => ["payload.labels.instance"], "quiet_sec" => 300}
    assert rule.present["title"] == "Pricing slow on {{payload.labels.instance}}"
    assert rule.notify == [%{"type" => "team", "id" => team.id}]
  end

  test "a draft that misses the test event is flagged", %{conn: conn, team: team, shape: shape} do
    answer(team, %{
      "conditions" => %{"all" => [%{"field" => "source", "op" => "eq", "value" => "other"}]}
    })

    {:ok, view, _html} = live(conn, ~p"/rules/new?#{[from_unmatched: shape.id]}")
    view |> element("#ai-draft-button") |> render_click()
    render_async(view)

    assert has_element?(view, "#ai-draft-mismatch")
  end

  test "an AI failure is explained and leaves the draft alone", %{conn: conn, shape: shape} do
    Application.put_env(:minion, :ai_stub_response, {:error, :not_configured})
    {:ok, view, _html} = live(conn, ~p"/rules/new?#{[from_unmatched: shape.id]}")

    view |> element("#ai-draft-button") |> render_click()
    render_async(view)

    assert has_element?(view, "#ai-draft-error", "GEMINI_API_KEY")
  end

  test "without a test event the button waits", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules/new")

    assert has_element?(view, "#ai-draft-button[disabled]")
    assert has_element?(view, "#ai-draft-status", "Paste an event")
  end

  test "editing an existing rule does not offer AI drafting", %{conn: conn, team: team} do
    rule = rule_fixture(team)
    {:ok, view, _html} = live(conn, ~p"/rules/#{rule.id}")

    refute has_element?(view, "#ai-draft")
  end
end
