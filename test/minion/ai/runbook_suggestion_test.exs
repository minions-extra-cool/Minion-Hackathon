defmodule Minion.AI.RunbookSuggestionTest do
  use ExUnit.Case, async: true

  alias Minion.AI.RunbookSuggestion
  alias Minion.Alerts.Alert

  @alert %Alert{
    title: "Disk full on web-1",
    severity: :warning,
    sample_event: %{"source" => "ops-monitor", "payload" => %{"host" => "web-1"}}
  }

  defmodule Answers do
    @behaviour Minion.AI.Provider

    @impl true
    def generate(prompt, _opts) do
      send(self(), {:prompt, prompt})
      Process.get(:answer)
    end
  end

  test "the prompt carries the current runbook, the note and the event" do
    Process.put(:answer, {:ok, "1. Rotate logs on {{payload.host}}"})

    assert {:ok, "1. Rotate logs on {{payload.host}}"} =
             RunbookSuggestion.suggest(
               @alert,
               "1. Check {{payload.host}}",
               "rotated logs",
               Answers
             )

    assert_received {:prompt, prompt}
    assert prompt =~ "1. Check {{payload.host}}"
    assert prompt =~ "rotated logs"
    assert prompt =~ ~s("host": "web-1")
    assert prompt =~ "keep its format"
  end

  test "without a runbook it asks for a new one" do
    prompt = RunbookSuggestion.build_prompt(@alert, nil, "restarted")
    assert prompt =~ "There is no runbook yet"
  end

  test "code fences and blank answers are handled" do
    Process.put(:answer, {:ok, "```markdown\n# Disk full\n1. Rotate\n```"})
    assert {:ok, "# Disk full\n1. Rotate"} = RunbookSuggestion.suggest(@alert, nil, "x", Answers)

    Process.put(:answer, {:ok, "   "})
    assert {:error, :empty_response} = RunbookSuggestion.suggest(@alert, nil, "x", Answers)
  end
end
