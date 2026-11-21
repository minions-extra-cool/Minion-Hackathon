defmodule Minion.AI.Summary do
  alias Minion.Alerts.Alert
  alias Minion.Rules.Template
  alias Minion.Runbooks

  @max_payload_chars 6_000
  @max_runbook_chars 4_000

  @spec summarize(Alert.t(), module()) :: {:ok, String.t()} | {:error, term()}
  def summarize(%Alert{} = alert, client \\ default_client()) do
    client.generate(build_prompt(alert))
  end

  defp default_client, do: Application.get_env(:minion, :ai_client, Minion.AI.Gemini)

  @spec build_prompt(Alert.t()) :: String.t()
  def build_prompt(%Alert{} = alert) do
    details =
      [
        {"Title", alert.title},
        {"Severity", to_string(alert.severity)},
        {"Status", status_text(alert)},
        {"Events seen", to_string(alert.count)},
        {"First event", timestamp(alert.first_seen)},
        {"Last event", timestamp(alert.last_seen)},
        {"Rule", rule_name(alert)},
        {"Body", alert.body}
      ]
      |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
      |> Enum.map_join("\n", fn {label, value} -> "#{label}: #{value}" end)

    fields =
      field_sections(alert)
      |> Enum.map_join("\n", fn {path, value} -> "  #{path} = #{value}" end)

    fields_block = if fields == "", do: "", else: "\nFields:\n#{fields}"

    """
    You are the on-call assistant for an engineering team. Summarise the alert below for the engineer who has to act on it.
    Write short plain text: what happened, why it matters, and concrete next steps. When the team's runbook is given, base the next steps on it. Do not invent facts. Keep it under 200 words.

    #{details}#{fields_block}#{runbook_block(alert)}

    Payload of the first event:
    #{payload(alert.sample_event)}
    """
  end

  defp field_sections(%{rule: %{present: %{"fields" => paths}}} = alert) when is_list(paths) do
    Enum.map(paths, fn path -> {path, Template.render("{{#{path}}}", alert.sample_event)} end)
  end

  defp field_sections(_alert), do: []

  defp runbook_block(alert) do
    runbook = Runbooks.get_for_rule(alert.rule_id)

    if Runbooks.blank?(runbook) do
      ""
    else
      rendered = runbook |> Runbooks.render(alert.sample_event) |> truncate(@max_runbook_chars)
      "\n\nTeam runbook for this rule:\n#{rendered}"
    end
  end

  defp payload(sample_event) do
    sample_event
    |> Jason.encode!(pretty: true)
    |> truncate(@max_payload_chars)
  end

  defp truncate(text, limit) when byte_size(text) <= limit, do: text
  defp truncate(text, limit), do: String.slice(text, 0, limit) <> "\n(truncated)"

  defp status_text(%Alert{status: status} = alert) do
    if alert.closed_at, do: "#{status}, closed by quiet time", else: to_string(status)
  end

  defp rule_name(%{rule: %{name: name}}) when is_binary(name), do: name
  defp rule_name(_alert), do: nil

  defp timestamp(nil), do: nil
  defp timestamp(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
end
