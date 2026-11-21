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
      "notify" => [],
      "send_by" => "preferences",
      "channels" => []
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
      "dedup_key" => list_text(dedup["key"]),
      "quiet_min" => quiet_minutes(dedup["quiet_sec"]),
      "title" => text(present["title"]),
      "body" => text(present["body"]),
      "fields" => list_text(present["fields"]),
      "color" => text(present["color"]),
      "notify" => for(%{"type" => type, "id" => id} <- rule.notify || [], do: "#{type}:#{id}")
    }
    |> Map.merge(send_by(rule.notify || []))
  end

  defp list_text(items) when is_list(items),
    do: items |> Enum.filter(&is_binary/1) |> Enum.join(", ")

  defp list_text(item) when is_binary(item), do: item
  defp list_text(_other), do: ""

  defp text(value) when is_binary(value), do: value
  defp text(_other), do: ""

  @spec from_attrs(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def from_attrs(attrs) do
    changeset = Rule.cast_changeset(%Rule{}, attrs)

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
          entry = %{"type" => type, "id" => id}

          if draft["send_by"] == "fixed",
            do: Map.put(entry, "channels", draft["channels"]),
            else: entry
        end)
    }
  end

  @spec put_params(map(), map()) :: map()
  def put_params(draft, params) do
    draft
    |> Map.merge(
      Map.take(
        params,
        ~w(name owner severity dedup_key quiet_min title body fields color send_by)
      )
    )
    |> put_enabled(params)
    |> put_notify(params)
    |> put_conditions(params)
  end

  defp put_enabled(draft, %{"enabled" => value}), do: Map.put(draft, "enabled", value == "true")
  defp put_enabled(draft, _params), do: draft

  defp put_notify(draft, params) do
    draft
    |> put_list(params, "notify")
    |> put_list(params, "channels")
  end

  defp put_list(draft, params, key) do
    case params do
      %{^key => values} when is_list(values) ->
        Map.put(draft, key, Enum.reject(values, &(&1 == "")))

      _ ->
        draft
    end
  end

  defp send_by([]), do: %{"send_by" => "preferences", "channels" => []}

  defp send_by(entries) do
    case entries |> Enum.map(&Map.get(&1, "channels")) |> Enum.uniq() do
      [channels] when is_list(channels) and channels != [] ->
        %{"send_by" => "fixed", "channels" => channels}

      _ ->
        %{"send_by" => "preferences", "channels" => []}
    end
  end

  defp put_conditions(draft, params) do
    tree =
      params
      |> path_entries("g")
      |> Enum.reduce(draft["conditions"], fn {path, mode}, tree ->
        if group_at?(tree, path) and mode in ["all", "any"],
          do: ConditionTree.set_mode(tree, path, mode),
          else: tree
      end)

    tree =
      params
      |> path_entries("c")
      |> Enum.reduce(tree, fn {path, leaf}, tree ->
        if leaf_at?(tree, path) and is_map(leaf) do
          ConditionTree.put_leaf(
            tree,
            path,
            leaf["field"] || "",
            leaf["op"] || "eq",
            leaf["value"] || ""
          )
        else
          tree
        end
      end)

    Map.put(draft, "conditions", tree)
  end

  defp path_entries(params, key) do
    params
    |> Map.get(key, %{})
    |> Enum.filter(fn {id, _value} -> id =~ ~r/\A(root|\d+(-\d+)*)\z/ end)
    |> Enum.map(fn {id, value} -> {ConditionTree.parse_path_id(id), value} end)
  end

  defp group_at?(tree, path) do
    case ConditionTree.node_at(tree, path) do
      {:ok, node} -> ConditionTree.group?(node)
      :error -> false
    end
  end

  defp leaf_at?(tree, path) do
    case ConditionTree.node_at(tree, path) do
      {:ok, node} -> not ConditionTree.group?(node)
      :error -> false
    end
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
