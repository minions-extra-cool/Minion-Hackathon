defmodule Minion.AI.RunbookSuggestion do
  alias Minion.Alerts.Alert

  @max_event_chars 4_000
  @max_output_tokens 4_096

  @spec suggest(Alert.t(), String.t() | nil, String.t(), module()) ::
          {:ok, String.t()} | {:error, term()}
  def suggest(%Alert{} = alert, runbook, note, client \\ Minion.AI.client()) do
    with {:ok, text} <-
           client.generate(build_prompt(alert, runbook, note),
             max_output_tokens: @max_output_tokens
           ) do
      case strip_fences(text) do
        "" -> {:error, :empty_response}
        body -> {:ok, body}
      end
    end
  end

  @spec build_prompt(Alert.t(), String.t() | nil, String.t()) :: String.t()
  def build_prompt(%Alert{} = alert, runbook, note) do
    current =
      if is_binary(runbook) and String.trim(runbook) != "",
        do: "The team's current runbook (keep its format and voice):\n<<<\n#{runbook}\n>>>",
        else:
          "There is no runbook yet. Write a short one in Markdown: a title line and numbered steps."

    """
    You maintain on-call runbooks. An engineer just resolved an alert and wrote down what fixed it. Update the runbook so the next person who gets this alert can fix it faster.

    Answer with the complete updated runbook text only: no preamble, no explanation, no code fences around it.
    - Keep everything in the current runbook that is still right; add or reorder steps to include what fixed it.
    - Keep {{payload.<path>}} placeholders. Where the note names a value from this event that changes per alert (a host, an id, a region), write the placeholder instead, using the event's paths below.
    - Do not invent commands, links or facts that are not in the runbook, the note or the event.
    - Keep it short.

    Alert: #{alert.title}
    Rule: #{rule_name(alert)}
    Severity: #{alert.severity}

    #{current}

    What fixed it, in the engineer's words:
    <<<
    #{note}
    >>>

    The event that opened the alert:
    #{alert.sample_event |> Jason.encode!(pretty: true) |> truncate()}
    """
  end

  defp strip_fences(text) do
    text
    |> String.trim()
    |> String.replace(~r/\A```[a-z]*\s*\n|\n?```\z/, "")
    |> String.trim()
  end

  defp rule_name(%{rule: %{name: name}}) when is_binary(name), do: name
  defp rule_name(_alert), do: "unknown"

  defp truncate(text) when byte_size(text) <= @max_event_chars, do: text
  defp truncate(text), do: String.slice(text, 0, @max_event_chars) <> "\n(truncated)"
end
