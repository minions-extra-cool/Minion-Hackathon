defmodule Minion.MetricsTest do
  use ExUnit.Case

  alias Minion.Metrics

  setup do
    Metrics.reset()
    :ok
  end

  test "reports percentiles of recorded latencies within the bucket precision" do
    for ms <- 1..100, do: Metrics.record(ms * 1000)

    %{processed: 100, latency_ms: %{p50: p50, p99: p99, max: max}} = Metrics.snapshot()

    assert_in_delta p50, 50, 50 * 0.06
    assert_in_delta p99, 99, 99 * 0.06
    assert max == 100.0
  end

  test "reset clears the counts and an empty histogram has no percentiles" do
    Metrics.record(5_000)
    Metrics.reset()

    assert %{processed: 0, latency_ms: %{p50: nil}} = Metrics.snapshot()
  end
end
