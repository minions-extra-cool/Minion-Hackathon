defmodule Minion.AI.RuleDraftTest do
  use ExUnit.Case, async: true

  alias Minion.AI.RuleDraft

  @team_id "6f1c2a7b-9e11-4a43-9d8e-0b6c3f4e2d0a"
  @owner "team:#{@team_id}"
  @notify_options [
    %{value: "team:#{@team_id}", label: "Everyone in settlements"},
    %{value: "oncall:#{@team_id}", label: "On call for settlements"}
  ]

  @event %{
    "source" => "workflows",
    "source_type" => "kafka",
    "payload" => %{
      "type" => "WORKFLOW_FAILED",
      "workflowId" => "WF-248358",
      "workflowName" => "Order-settlement",
      "severity" => "ERROR"
    }
  }

  @answer %{
    "name" => "Workflow failed",
    "severity" => "critical",
    "conditions" => %{
      "all" => [
        %{"field" => "source", "op" => "eq", "value" => "workflows"},
        %{"field" => "payload.type", "op" => "eq", "value" => "WORKFLOW_FAILED"}
      ]
    },
    "dedup" => %{"key" => ["payload.workflowId"], "quiet_sec" => 600},
    "present" => %{
      "title" => "{{payload.workflowName}} failed",
      "body" => "Workflow {{payload.workflowId}} failed.",
      "fields" => ["payload.workflowId"],
      "color" => "red"
    },
    "notify" => [
      %{"type" => "oncall", "id" => @team_id},
      %{"type" => "person", "id" => "00000000-0000-0000-0000-000000000000"}
    ]
  }

  defmodule Answers do
    @behaviour Minion.AI.Provider

    @impl true
    def generate(_prompt, opts) do
      send(self(), {:opts, opts})
      Process.get(:answer)
    end
  end

  defp answer(value), do: Process.put(:answer, value)

  test "turns the AI's JSON into an editor draft that matches the event" do
    answer({:ok, "```json\n" <> Jason.encode!(@answer) <> "\n```"})

    assert {:ok, %{draft: draft, matches_sample?: true}} =
             RuleDraft.suggest(@event, @owner, @notify_options, Answers)

    assert_received {:opts, opts}
    assert opts[:json]

    assert draft["name"] == "Workflow failed"
    assert draft["severity"] == "critical"
    assert draft["owner"] == @owner
    assert draft["title"] == "{{payload.workflowName}} failed"
    assert draft["notify"] == ["oncall:#{@team_id}"]
  end

  test "reports a draft that does not match the event" do
    answer(
      {:ok,
       Jason.encode!(
         put_in(@answer, ["conditions", "all", Access.at(1), "value"], "SOMETHING_ELSE")
       )}
    )

    assert {:ok, %{matches_sample?: false}} =
             RuleDraft.suggest(@event, @owner, @notify_options, Answers)
  end

  test "a reply that is not JSON is an error" do
    answer({:ok, "Sure! Here is a rule you might like."})
    assert {:error, :not_json} = RuleDraft.suggest(@event, @owner, @notify_options, Answers)
  end

  test "an invalid rule is an error naming the bad parts" do
    answer({:ok, Jason.encode!(Map.put(@answer, "severity", "apocalyptic"))})

    assert {:error, {:invalid, %{severity: _}}} =
             RuleDraft.suggest(@event, @owner, @notify_options, Answers)
  end

  test "provider errors pass through" do
    answer({:error, :not_configured})
    assert {:error, :not_configured} = RuleDraft.suggest(@event, @owner, @notify_options, Answers)
  end

  test "the prompt carries the contract, the event and only the allowed notify targets" do
    prompt = RuleDraft.build_prompt(@event, @notify_options)

    assert prompt =~ ~s("value": "workflows")
    assert prompt =~ "WORKFLOW_FAILED"
    assert prompt =~ ~s({"type": "oncall", "id": "#{@team_id}"})
    assert prompt =~ "On call for settlements"
    assert prompt =~ "Operators: eq, neq"
  end
end
