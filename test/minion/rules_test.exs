defmodule Minion.RulesTest do
  use Minion.DataCase, async: true

  import Minion.AlertFixtures

  alias Minion.Rules
  alias Minion.Rules.{Draft, Rule}

  setup do
    team = team_fixture()

    attrs = %{
      "name" => "Disk full",
      "owner_type" => "team",
      "owner_id" => team.id,
      "severity" => "warning",
      "conditions" => %{
        "all" => [%{"field" => "payload.type", "op" => "eq", "value" => "DISK_FULL"}]
      },
      "dedup" => %{"key" => ["payload.host"], "quiet_sec" => 600},
      "present" => %{"title" => "Disk full on {{payload.host}}"},
      "notify" => [%{"type" => "team", "id" => team.id}]
    }

    %{team: team, attrs: attrs}
  end

  defp errors(attrs), do: %Rule{} |> Rule.changeset(attrs) |> errors_on()

  test "creates a valid rule and tells subscribers", %{attrs: attrs} do
    Phoenix.PubSub.subscribe(Minion.PubSub, Rules.topic())

    assert {:ok, %Rule{id: id}} = Rules.create_rule(attrs)
    assert_received {:rules_changed, ^id}
  end

  test "set_enabled turns a rule off and on", %{attrs: attrs} do
    {:ok, rule} = Rules.create_rule(attrs)

    assert {:ok, %Rule{enabled: false} = rule} = Rules.set_enabled(rule, false)
    assert {:ok, %Rule{enabled: true}} = Rules.set_enabled(rule, true)
  end

  describe "validation" do
    test "needs at least one condition", %{attrs: attrs} do
      assert %{conditions: ["need at least one condition"]} =
               errors(%{attrs | "conditions" => %{"all" => []}})
    end

    test "every condition needs a field and, except exists, a value", %{attrs: attrs} do
      no_field = %{"all" => [%{"field" => "", "op" => "eq", "value" => "x"}]}
      no_value = %{"all" => [%{"field" => "payload.type", "op" => "eq", "value" => ""}]}
      exists = %{"all" => [%{"field" => "payload.error", "op" => "exists", "value" => nil}]}

      assert %{conditions: ["every condition needs a field"]} =
               errors(%{attrs | "conditions" => no_field})

      assert %{conditions: [~s("payload.type" needs a value)]} =
               errors(%{attrs | "conditions" => no_value})

      refute Map.has_key?(errors(%{attrs | "conditions" => exists}), :conditions)
    end

    test "rejects unknown operators and an empty 'is one of'", %{attrs: attrs} do
      unknown = %{"all" => [%{"field" => "a", "op" => "between", "value" => "1"}]}
      empty_in = %{"all" => [%{"field" => "a", "op" => "in", "value" => []}]}

      assert %{conditions: [~s(has an unknown operator "between")]} =
               errors(%{attrs | "conditions" => unknown})

      assert %{conditions: [~s("a is one of" needs at least one value)]} =
               errors(%{attrs | "conditions" => empty_in})
    end

    test "checks grouping and notify entries", %{attrs: attrs} do
      assert %{dedup: [_]} = errors(%{attrs | "dedup" => %{"quiet_sec" => -5}})
      assert %{notify: [_]} = errors(%{attrs | "notify" => [%{"type" => "pager"}]})
    end
  end

  describe "Draft" do
    test "round-trips a rule through the editor's draft", %{attrs: attrs} do
      {:ok, rule} = Rules.create_rule(attrs)
      round_tripped = rule |> Draft.from_rule() |> Draft.to_attrs()

      assert round_tripped["conditions"] == attrs["conditions"]
      assert round_tripped["dedup"] == attrs["dedup"]
      assert round_tripped["present"] == attrs["present"]
      assert round_tripped["notify"] == attrs["notify"]

      assert {round_tripped["owner_type"], round_tripped["owner_id"]} ==
               {"team", attrs["owner_id"]}
    end

    test "ignores params for positions that no longer exist or hold the other kind of node", %{
      team: team
    } do
      draft = Draft.new("team:#{team.id}")

      updated =
        Draft.put_params(draft, %{
          "g" => %{"0" => "any", "7" => "any"},
          "c" => %{"root" => %{"field" => "x"}, "3-1" => %{"field" => "y"}}
        })

      assert updated["conditions"] == draft["conditions"]
    end

    test "applies form params to conditions, groups, notify and enabled", %{team: team} do
      draft =
        Draft.new("team:#{team.id}")
        |> Draft.put_params(%{
          "name" => "Rejected trades",
          "g" => %{"root" => "any"},
          "c" => %{"0" => %{"field" => "payload.notional", "op" => "gt", "value" => "100000"}},
          "notify" => ["", "oncall:#{team.id}"],
          "enabled" => "false",
          "quiet_min" => "5"
        })

      attrs = Draft.to_attrs(draft)

      assert attrs["conditions"] == %{
               "any" => [%{"field" => "payload.notional", "op" => "gt", "value" => "100000"}]
             }

      assert attrs["notify"] == [%{"type" => "oncall", "id" => team.id}]
      assert attrs["enabled"] == false
      assert attrs["dedup"] == %{"quiet_sec" => 300}
    end
  end
end
