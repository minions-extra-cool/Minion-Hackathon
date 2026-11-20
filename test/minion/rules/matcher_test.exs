defmodule Minion.Rules.MatcherTest do
  use ExUnit.Case, async: true

  alias Minion.Rules.Matcher

  defp event(payload, source \\ "test"), do: %{"source" => source, "payload" => payload}

  defp condition(field, op, value), do: %{"field" => field, "op" => op, "value" => value}

  defp matches?(condition, payload), do: Matcher.matches?(condition, event(payload))

  describe "eq and neq" do
    test "compare strings case-insensitively" do
      assert matches?(condition("payload.workflowName", "eq", "order-settlement"), %{
               "workflowName" => "Order-settlement"
             })

      refute matches?(condition("payload.env", "eq", "prod"), %{"env" => "staging"})
      assert matches?(condition("payload.env", "neq", "prod"), %{"env" => "staging"})
    end

    test "compare numbers by value, whether sent as numbers or strings" do
      assert matches?(condition("payload.status", "eq", "500"), %{"status" => 500})
      assert matches?(condition("payload.status", "eq", 500), %{"status" => "500"})
      assert matches?(condition("payload.ratio", "eq", 1), %{"ratio" => 1.0})
    end

    test "compare booleans and null" do
      assert matches?(condition("payload.retryable", "eq", "true"), %{"retryable" => true})
      assert matches?(condition("payload.owner", "eq", nil), %{"owner" => nil})
    end
  end

  describe "numeric comparisons" do
    test "gt, gte, lt and lte" do
      payload = %{"notional" => 250_000}

      assert matches?(condition("payload.notional", "gt", 100_000), payload)
      refute matches?(condition("payload.notional", "gt", 250_000), payload)
      assert matches?(condition("payload.notional", "gte", 250_000), payload)
      assert matches?(condition("payload.notional", "lt", "300000"), payload)
      refute matches?(condition("payload.notional", "lte", 1), payload)
    end

    test "accept numbers sent as strings" do
      assert matches?(condition("payload.latency_ms", "gt", 1000), %{"latency_ms" => "1200.5"})
    end

    test "are false when either side is not a number" do
      refute matches?(condition("payload.notional", "gt", 1), %{"notional" => "large"})
      refute matches?(condition("payload.notional", "gt", "abc"), %{"notional" => 5})
    end
  end

  describe "in and contains" do
    test "in checks the field against a list of values" do
      condition = condition("payload.error.code", "in", ["TIMEOUT", "REJECTED"])

      assert matches?(condition, %{"error" => %{"code" => "rejected"}})
      refute matches?(condition, %{"error" => %{"code" => "NOT_FOUND"}})
    end

    test "contains finds a substring in a string field" do
      assert matches?(condition("payload", "contains", "latency"), "WARN pricing latency 1200ms")
      refute matches?(condition("payload", "contains", "error"), "WARN pricing latency 1200ms")
    end

    test "contains finds an element in a list field" do
      assert matches?(condition("payload.tags", "contains", "PCI"), %{
               "tags" => ["pci", "payments"]
             })

      refute matches?(condition("payload.tags", "contains", "gdpr"), %{"tags" => ["pci"]})
    end
  end

  describe "matches" do
    test "supports * wildcards over the whole value" do
      condition = condition("source", "matches", "pricing-engine-*")

      assert Matcher.matches?(condition, event(%{}, "pricing-engine-3"))
      assert Matcher.matches?(condition, event(%{}, "Pricing-Engine-12"))
      refute Matcher.matches?(condition, event(%{}, "old-pricing-engine-3"))
    end

    test "treats regex characters in the pattern literally" do
      assert matches?(condition("payload.meta.schema", "matches", "trade.rejected.*"), %{
               "meta" => %{"schema" => "trade.rejected.v2"}
             })

      refute matches?(condition("payload.meta.schema", "matches", "trade.rejected.*"), %{
               "meta" => %{"schema" => "tradeXrejected.v2"}
             })
    end
  end

  describe "exists" do
    test "is true only for a present, non-null field" do
      assert matches?(condition("payload.error", "exists", nil), %{"error" => %{}})
      refute matches?(condition("payload.error", "exists", nil), %{"error" => nil})
      refute matches?(condition("payload.error", "exists", nil), %{})
    end
  end

  describe "missing fields and invalid conditions" do
    test "a missing field makes any condition false, including neq" do
      refute matches?(condition("payload.env", "eq", "prod"), %{})
      refute matches?(condition("payload.env", "neq", "prod"), %{})
      refute matches?(condition("payload.env.name", "eq", "prod"), %{"env" => "prod"})
    end

    test "a payload that is plain text has no nested fields" do
      refute matches?(condition("payload.level", "eq", "WARN"), "WARN latency 1200ms")
    end

    test "an unknown operator or a malformed node is false, never an error" do
      refute matches?(condition("payload.env", "between", [1, 2]), %{"env" => 1})
      refute Matcher.matches?(%{"nonsense" => true}, event(%{}))
      refute Matcher.matches?(%{"all" => "not a list"}, event(%{}))
    end
  end

  describe "all and any" do
    test "all is AND, any is OR, and they nest" do
      settlements = %{
        "all" => [
          condition("payload.type", "eq", "WORKFLOW_FAILED"),
          condition("payload.environment", "eq", "prod"),
          %{
            "any" => [
              condition("payload.error.code", "in", ["TIMEOUT", "REJECTED"]),
              condition("payload.amount", "gt", 1_000_000)
            ]
          }
        ]
      }

      base = %{"type" => "WORKFLOW_FAILED", "environment" => "prod"}

      assert matches?(settlements, Map.put(base, "error", %{"code" => "TIMEOUT"}))
      assert matches?(settlements, Map.put(base, "amount", 2_000_000))
      refute matches?(settlements, Map.put(base, "amount", 10))

      refute matches?(
               settlements,
               %{base | "environment" => "uat"} |> Map.put("amount", 2_000_000)
             )
    end
  end
end
