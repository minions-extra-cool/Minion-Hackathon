defmodule Minion.Rules.ConditionTree do
  alias Minion.Rules.Matcher

  @ops ~w(eq neq gt gte lt lte in contains matches exists)
  @op_labels %{
    "eq" => "equals",
    "neq" => "does not equal",
    "gt" => ">",
    "gte" => "≥",
    "lt" => "<",
    "lte" => "≤",
    "in" => "is one of",
    "contains" => "contains",
    "matches" => "matches",
    "exists" => "exists"
  }

  @type path :: [non_neg_integer()]

  def ops, do: @ops
  def op_label(op), do: Map.get(@op_labels, op, op)

  def new_leaf, do: %{"field" => "", "op" => "eq", "value" => ""}
  def new_tree, do: %{"all" => [new_leaf()]}

  def normalize(%{"all" => children}) when is_list(children), do: %{"all" => children}
  def normalize(%{"any" => children}) when is_list(children), do: %{"any" => children}
  def normalize(%{} = leaf), do: %{"all" => [leaf]}
  def normalize(_other), do: new_tree()

  def group?(node), do: is_map_key(node, "all") or is_map_key(node, "any")

  def mode(%{"any" => _}), do: "any"
  def mode(_group), do: "all"

  def children(%{"all" => children}), do: children
  def children(%{"any" => children}), do: children

  defp put_children(group, children), do: %{mode(group) => children}

  @spec update_at(map(), path(), (map() -> map())) :: map()
  def update_at(node, [], fun), do: fun.(node)

  def update_at(group, [index | rest], fun) do
    put_children(group, List.update_at(children(group), index, &update_at(&1, rest, fun)))
  end

  def add_leaf(tree, group_path),
    do: update_at(tree, group_path, &put_children(&1, children(&1) ++ [new_leaf()]))

  def add_group(tree, group_path),
    do: update_at(tree, group_path, &put_children(&1, children(&1) ++ [%{"any" => [new_leaf()]}]))

  def remove_at(tree, path) do
    {parent, [index]} = Enum.split(path, -1)
    update_at(tree, parent, &put_children(&1, List.delete_at(children(&1), index)))
  end

  def set_mode(tree, group_path, mode) when mode in ["all", "any"],
    do: update_at(tree, group_path, &%{mode => children(&1)})

  def put_leaf(tree, path, field, op, value_text) do
    op = if op in @ops, do: op, else: "eq"

    update_at(tree, path, fn _leaf ->
      %{"field" => String.trim(field), "op" => op, "value" => parse_value(op, value_text)}
    end)
  end

  def parse_value("exists", _text), do: nil

  def parse_value("in", text) when is_binary(text),
    do: text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  def parse_value(_op, text) when is_binary(text), do: String.trim(text)
  def parse_value(_op, value), do: value

  def value_text(%{"value" => values}) when is_list(values), do: Enum.join(values, ", ")
  def value_text(%{"value" => nil}), do: ""
  def value_text(%{"value" => value}), do: to_string(value)
  def value_text(_leaf), do: ""

  def path_id([]), do: "root"
  def path_id(path), do: Enum.join(path, "-")

  def parse_path_id("root"), do: []
  def parse_path_id(id), do: id |> String.split("-") |> Enum.map(&String.to_integer/1)

  def leaves(node, path \\ [])

  def leaves(node, path) do
    if group?(node) do
      node
      |> children()
      |> Enum.with_index()
      |> Enum.flat_map(fn {child, i} -> leaves(child, path ++ [i]) end)
    else
      [{path, node}]
    end
  end

  def complete_leaf?(%{"field" => field, "op" => "exists"}), do: field != ""

  def complete_leaf?(%{"field" => field, "value" => value}),
    do: field != "" and value not in [nil, "", []]

  def complete_leaf?(_leaf), do: false

  def evaluate(tree, envelope) do
    tree
    |> leaves()
    |> Map.new(fn {path, leaf} ->
      {path, complete_leaf?(leaf) and Matcher.matches?(leaf, envelope)}
    end)
  end

  def describe(node) do
    cond do
      not group?(node) ->
        describe_leaf(node)

      children(node) == [] ->
        "nothing"

      true ->
        joiner = if mode(node) == "all", do: " and ", else: " or "

        node
        |> children()
        |> Enum.map(fn child ->
          if group?(child), do: "(#{describe(child)})", else: describe(child)
        end)
        |> Enum.join(joiner)
    end
  end

  defp describe_leaf(%{"field" => field, "op" => "exists"}), do: "#{field} exists"

  defp describe_leaf(%{"field" => field, "op" => op} = leaf),
    do: "#{field} #{op_label(op)} #{value_text(leaf)}"

  defp describe_leaf(_invalid), do: "invalid condition"
end
