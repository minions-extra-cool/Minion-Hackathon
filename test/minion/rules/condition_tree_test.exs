defmodule Minion.Rules.ConditionTreeTest do
  use ExUnit.Case, async: true

  alias Minion.Rules.{ConditionTree, Path}

  defp leaf(field, op, value), do: %{"field" => field, "op" => op, "value" => value}

  @tree %{
    "all" => [
      %{"field" => "payload.type", "op" => "eq", "value" => "DISK_FULL"},
      %{"any" => [%{"field" => "payload.used", "op" => "gt", "value" => "90"}]}
    ]
  }

  test "adds conditions and groups, and removes them by path" do
    tree =
      @tree
      |> ConditionTree.add_leaf([1])
      |> ConditionTree.add_group([])

    assert [_, %{"any" => [_, %{"field" => ""}]}, %{"any" => [%{"field" => ""}]}] = tree["all"]

    assert %{"all" => [_, %{"any" => [_]}]} =
             tree |> ConditionTree.remove_at([2]) |> ConditionTree.remove_at([1, 1])
  end

  test "switches a group between all and any" do
    assert %{"any" => [_, _]} = ConditionTree.set_mode(@tree, [], "any")
    assert %{"all" => [_, %{"all" => [_]}]} = ConditionTree.set_mode(@tree, [1], "all")
  end

  test "parses values by operator" do
    tree = ConditionTree.put_leaf(@tree, [0], " payload.code ", "in", "TIMEOUT, REJECTED ,")

    assert %{"field" => "payload.code", "op" => "in", "value" => ["TIMEOUT", "REJECTED"]} =
             hd(tree["all"])

    tree = ConditionTree.put_leaf(@tree, [0], "payload.error", "exists", "ignored")
    assert %{"value" => nil} = hd(tree["all"])
  end

  test "describes a tree as a sentence" do
    assert ConditionTree.describe(@tree) ==
             "payload.type equals DISK_FULL and (payload.used > 90)"

    assert ConditionTree.describe(%{
             "any" => [
               leaf("source", "matches", "pricing-*"),
               leaf("payload.code", "in", ["A", "B"])
             ]
           }) ==
             "source matches pricing-* or payload.code is one of A, B"
  end

  test "evaluates each complete condition against an event" do
    event = %{"payload" => %{"type" => "DISK_FULL", "used" => 80}}
    tree = ConditionTree.add_leaf(@tree, [])

    assert ConditionTree.evaluate(tree, event) == %{[0] => true, [1, 0] => false, [2] => false}
  end

  test "path ids round-trip" do
    assert ConditionTree.path_id([]) == "root"
    assert ConditionTree.path_id([1, 0]) == "1-0"
    assert ConditionTree.parse_path_id("1-0") == [1, 0]
    assert ConditionTree.parse_path_id("root") == []
  end

  test "Path.list lists every leaf path of an event" do
    event = %{
      "source" => "api",
      "payload" => %{"labels" => %{"service" => "x"}, "errors" => [%{"code" => 1}]}
    }

    assert Path.list(event) == ["payload.errors.0.code", "payload.labels.service", "source"]
  end
end
