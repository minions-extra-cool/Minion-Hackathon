defmodule Minion.UnmatchedTest do
  use Minion.DataCase, async: true

  import Minion.AlertFixtures

  alias Minion.Alerts.Processor
  alias Minion.Rules.Matcher
  alias Minion.Unmatched
  alias Minion.Unmatched.Shape

  defp event(source, payload), do: Minion.Ingest.envelope(source, "http", payload)

  test "groups events by source and shape, counting repeats" do
    Unmatched.subscribe()

    first = Unmatched.record(event("ops-monitor", %{"type" => "CPU_HIGH", "host" => "web-1"}))
    second = Unmatched.record(event("ops-monitor", %{"type" => "CPU_HIGH", "host" => "web-2"}))

    assert second.id == first.id
    assert second.count == 2
    assert second.paths == ["payload.host", "payload.type"]
    assert second.sample_event["payload"]["host"] == "web-2"
    assert_received {:unmatched, %Shape{count: 2}}
  end

  test "a different source, or different fields, is a different shape" do
    a = Unmatched.record(event("ops-monitor", %{"type" => "CPU_HIGH"}))
    b = Unmatched.record(event("billing", %{"type" => "CPU_HIGH"}))
    c = Unmatched.record(event("ops-monitor", %{"type" => "CPU_HIGH", "extra" => 1}))

    assert length(Enum.uniq([a.id, b.id, c.id])) == 3
  end

  test "plain-text events from one source share a shape" do
    a = Unmatched.record(event("pricing-engine", "WARN latency 1200ms"))
    b = Unmatched.record(event("pricing-engine", "WARN latency 900ms"))

    assert a.id == b.id
    assert b.paths == []
  end

  test "dismiss removes a shape and tells subscribers" do
    shape = Unmatched.record(event("ops-monitor", %{"type" => "CPU_HIGH"}))
    Unmatched.subscribe()

    Unmatched.dismiss(shape.id)

    assert Unmatched.get(shape.id) == nil
    assert_received {:dismissed, id}
    assert id == shape.id
  end

  test "prune drops shapes not seen for 24 hours" do
    shape = Unmatched.record(event("ops-monitor", %{"type" => "CPU_HIGH"}))

    assert Unmatched.prune(DateTime.add(shape.last_seen, 23, :hour)) == 0
    assert Unmatched.prune(DateTime.add(shape.last_seen, 25, :hour)) == 1
  end

  test "the processor records events that match no rule" do
    rule = team_fixture() |> rule_fixture()

    {:ok, []} = Processor.process(event("ops-monitor", %{"type" => "CPU_HIGH"}), [rule])
    {:ok, []} = Processor.process(event("ops-monitor", %{"type" => "MEM_HIGH"}), [])

    assert [%Shape{count: 2, source: "ops-monitor"}] = Repo.all(Shape)
  end

  describe "suggested_draft/2" do
    test "starts a rule that matches the shape's events" do
      shape =
        Unmatched.record(
          event("prometheus", %{"alertname" => "HighErrorRate", "labels" => %{"service" => "api"}})
        )

      draft = Unmatched.suggested_draft(shape, "team:abc")

      assert draft["name"] == "HighErrorRate from prometheus"
      assert draft["owner"] == "team:abc"

      assert draft["conditions"] == %{
               "all" => [
                 %{"field" => "source", "op" => "eq", "value" => "prometheus"},
                 %{"field" => "payload.alertname", "op" => "eq", "value" => "HighErrorRate"}
               ]
             }

      assert Matcher.matches?(draft["conditions"], shape.sample_event)
    end

    test "falls back to the source alone when nothing identifies the event" do
      shape = Unmatched.record(event("pricing-engine", "WARN latency 1200ms"))

      assert %{
               "name" => "events from pricing-engine",
               "conditions" => %{"all" => [%{"field" => "source"}]}
             } =
               Unmatched.suggested_draft(shape, nil)
    end
  end
end
