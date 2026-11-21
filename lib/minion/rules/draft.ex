defmodule Minion.Rules.Draft do
  alias Minion.Rules.{ConditionTree, Rule}

  @colors ~w(red amber green blue gray)

  def colors, do: @colors

  @spec new(String.t() | nil) :: map()
  def new(owner) do
    %{
      "name" => "",
      "owner" => owner || "",
      "enabled" => true,
      "severity" => "warning",
      "conditions" => ConditionTree.new_tree(),
      "dedup_key" => "",
      "quiet_min" => "10",
      "title" => "",
      "body" => "",
      "fields" => "",
      "color" => "",
      "notify" => []
    }
  end

  @spec from_rule(Rule.t()) :: map()
  def from_rule(%Rule{} = rule) do
    dedup = rule.dedup || %{}
    present = rule.present || %{}

    %{
      "name" => rule.name || "",
      "owner" => if(rule.owner_type, do: "#{rule.owner_type}:#{rule.owner_id}", else: ""),
      "enabled" => rule.enabled != false,
      "severity" => to_string(rule.severity || :warning),
      "conditions" => ConditionTree.normalize(rule.conditions),
      "dedup_key" => dedup |> Map.get("key", []) |> Enum.join(", "),
      "quiet_min" => quiet_minutes(dedup["quiet_sec"]),
      "title" => present["title"] || "",
      "body" => present["body"] || "",
      "fields" => present |> Map.get("fields", []) |> Enum.join(", "),
      "color" => present["color"] || "",
      "notify" => Enum.map(rule.notify || [], &"#{&1["type"]}:#{&1["id"]}")
    }
  end

  @spec from_attrs(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def from_attrs(attrs) do
    changeset = Rule.changeset(%Rule{}, attrs)

    if changeset.valid? do
      {:ok, changeset |> Ecto.Changeset.apply_changes() |> from_rule()}
    else
      {:error, changeset}
    end
  end

  @spec to_attrs(map()) :: map()
  def to_attrs(draft) do
    {owner_type, owner_id} = split_ref(draft["owner"])

    %{
      "name" => String.trim(draft["name"]),
      "owner_type" => owner_type,
      "owner_id" => owner_id,
      "enabled" => draft["enabled"],
      "severity" => draft["severity"],
      "conditions" => draft["conditions"],
      "dedup" =>
        compact(%{
          "key" => split_list(draft["dedup_key"]),
          "quiet_sec" => quiet_seconds(draft["quiet_min"])
        }),
      "present" =>
        compact(%{
          "title" => blank_to_nil(draft["title"]),
          "body" => blank_to_nil(draft["body"]),
          "fields" => split_list(draft["fields"]),
          "color" => blank_to_nil(draft["color"])
        }),
      "notify" =>
        Enum.map(draft["notify"], fn ref ->
          {type, id} = split_ref(ref)
          %{"type" => type, "id" => id}
        end)
    }
  end

  @spec put_params(map(), map()) :: map()
  def put_params(draft, params) do
    draft
    |> Map.merge(
      Map.take(params, ~w(name owner severity dedup_key quiet_min title body fields color))
    )
    |> put_enabled(params)
    |> put_notify(params)
    |> put_conditions(params)
  end

  defp put_enabled(draft, %{"enabled" => value}), do: Map.put(draft, "enabled", value == "true")
  defp put_enabled(draft, _params), do: draft

  defp put_notify(draft, %{"notify" => refs}) when is_list(refs),
    do: Map.put(draft, "notify", Enum.reject(refs, &(&1 == "")))

  defp put_notify(draft, _params), do: draft

  defp put_conditions(draft, params) do
    tree =
      params
      |> Map.get("g", %{})
      |> Enum.reduce(draft["conditions"], fn {id, mode}, tree ->
        ConditionTree.set_mode(tree, ConditionTree.parse_path_id(id), mode)
      end)

    tree =
      params
      |> Map.get("c", %{})
      |> Enum.reduce(tree, fn {id, leaf}, tree ->
        ConditionTree.put_leaf(
          tree,
          ConditionTree.parse_path_id(id),
          leaf["field"] || "",
          leaf["op"] || "eq",
          leaf["value"] || ""
        )
      end)

    Map.put(draft, "conditions", tree)
  end

  defp split_ref(ref) when is_binary(ref) do
    case String.split(ref, ":", parts: 2) do
      [type, id] -> {type, id}
      _ -> {nil, nil}
    end
  end

  defp split_ref(_ref), do: {nil, nil}

  defp split_list(text) when is_binary(text),
    do: text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp split_list(_text), do: []

  defp quiet_seconds(minutes) do
    case Integer.parse(to_string(minutes)) do
      {value, ""} when value > 0 -> value * 60
      _ -> nil
    end
  end

  defp quiet_minutes(seconds) when is_integer(seconds) and seconds > 0,
    do: to_string(div(seconds, 60))

  defp quiet_minutes(_seconds), do: ""

  defp blank_to_nil(text) when is_binary(text) do
    if String.trim(text) == "", do: nil, else: text
  end

  defp blank_to_nil(_text), do: nil

  defp compact(map),
    do: map |> Enum.reject(fn {_key, value} -> value in [nil, []] end) |> Map.new()
end
