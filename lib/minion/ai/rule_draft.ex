defmodule Minion.AI.RuleDraft do
  alias Minion.Rules.{Draft, Matcher, Rule}

  @max_event_chars 6_000
  @max_output_tokens 4_096

  @type result :: %{draft: map(), matches_sample?: boolean()}

  @spec suggest(map(), String.t() | nil, [%{value: String.t(), label: String.t()}], module()) ::
          {:ok, result()} | {:error, term()}
  def suggest(event, owner, notify_options, client \\ Minion.AI.client()) do
    prompt = build_prompt(event, notify_options)

    with {:ok, text} <- client.generate(prompt, json: true, max_output_tokens: @max_output_tokens),
         {:ok, attrs} <- decode(text),
         attrs = attrs |> put_owner(owner) |> keep_known_targets(notify_options),
         :ok <- validate(attrs),
         {:ok, draft} <- Draft.from_attrs(attrs) do
      {:ok, %{draft: draft, matches_sample?: Matcher.matches?(attrs["conditions"], event)}}
    end
  end

  @spec build_prompt(map(), [%{value: String.t(), label: String.t()}]) :: String.t()
  def build_prompt(event, notify_options) do
    targets =
      notify_options
      |> Enum.map(fn %{value: value, label: label} ->
        [type, id] = String.split(value, ":", parts: 2)
        ~s(  {"type": "#{type}", "id": "#{id}"}  -> #{label})
      end)
      |> Enum.join("\n")

    """
    You write alert routing rules for Minion. Given one event it has never seen, write a rule that matches events like it and makes a useful alert.

    Answer with a single JSON object and nothing else, in this shape:
    {
      "name": "short human name, e.g. Disk full",
      "severity": "info" | "warning" | "critical",
      "conditions": {"all": [ {"field": "...", "op": "...", "value": ...} ]},
      "dedup": {"key": ["payload.<field that tells instances apart>"], "quiet_sec": 600},
      "present": {"title": "...", "body": "...", "fields": ["payload.<path>"], "color": "red" | "amber" | "green" | "blue" | "gray"},
      "notify": [ {"type": "...", "id": "..."} ]
    }

    Rules for the rule:
    - Fields are dot paths into the event below, e.g. "source", "payload.type", "payload.labels.service", "payload.errors.0.code".
    - Operators: eq, neq, gt, gte, lt, lte, in (value is a list), contains, matches (value with * wildcards), exists (no value).
    - Conditions can nest: {"all": [...]} or {"any": [...]}, at most one level of nested groups.
    - Always include {"field": "source", "op": "eq", "value": "#{event["source"]}"} and one condition on a field that identifies this kind of event (a type, name, alertname or schema). Do not match on values that change per event (ids, timestamps, hosts, amounts).
    - The conditions must match the event below.
    - Severity: use a severity or level field in the event if there is one, otherwise judge from the content.
    - dedup.key: the paths that tell separate problems apart (host, service, workflow id). One alert per distinct value.
    - Templates use {{payload.path}} placeholders. The title is one short line; the body says what happened in a sentence.
    - fields: 2 to 4 paths an engineer needs at a glance.
    - color: red for critical, amber for warning, blue or gray for info, unless the event suggests otherwise.
    - notify: one or two entries, chosen only from this list (copy type and id exactly):
    #{targets}

    The event:
    #{event |> Jason.encode!(pretty: true) |> truncate()}
    """
  end

  defp decode(text) do
    text
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*|\s*```\z/, "")
    |> Jason.decode()
    |> case do
      {:ok, %{} = attrs} -> {:ok, Map.take(attrs, Rule.contract_fields())}
      _ -> {:error, :not_json}
    end
  end

  defp put_owner(attrs, owner) do
    case owner && String.split(owner, ":", parts: 2) do
      [type, id] when type in ["team", "person"] ->
        Map.merge(attrs, %{"owner_type" => type, "owner_id" => id})

      _ ->
        attrs
    end
  end

  defp keep_known_targets(attrs, notify_options) do
    known = MapSet.new(notify_options, & &1.value)

    notify =
      for %{"type" => type, "id" => id} = entry <- List.wrap(attrs["notify"]),
          MapSet.member?(known, "#{type}:#{id}"),
          do: Map.take(entry, ["type", "id", "channels"])

    Map.put(attrs, "notify", notify)
  end

  defp validate(attrs) do
    changeset = Rule.changeset(%Rule{}, attrs)

    if changeset.valid? do
      :ok
    else
      {:error,
       {:invalid, Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)}}
    end
  end

  defp truncate(text) when byte_size(text) <= @max_event_chars, do: text
  defp truncate(text), do: String.slice(text, 0, @max_event_chars) <> "\n(truncated)"
end
