defmodule Minion.Metrics do
  @event [:minion, :pipeline, :processed]
  @buckets 500
  @growth 1.05
  @key {__MODULE__, :histogram}

  def event, do: @event

  def setup do
    :persistent_term.put(@key, :counters.new(@buckets + 2, [:write_concurrency]))
    :telemetry.attach("minion-metrics", @event, &__MODULE__.handle_event/4, nil)
  end

  def handle_event(@event, %{latency_us: latency_us}, _metadata, _config) do
    counters = :persistent_term.get(@key)
    :counters.add(counters, bucket(latency_us), 1)
    :counters.add(counters, @buckets + 1, 1)
    :counters.put(counters, @buckets + 2, max(:counters.get(counters, @buckets + 2), latency_us))
  end

  @spec record(non_neg_integer()) :: :ok
  def record(latency_us), do: :telemetry.execute(@event, %{latency_us: latency_us}, %{})

  def reset do
    counters = :persistent_term.get(@key)
    Enum.each(1..(@buckets + 2), &:counters.put(counters, &1, 0))
  end

  def snapshot do
    counters = :persistent_term.get(@key)
    count = :counters.get(counters, @buckets + 1)

    %{
      processed: count,
      latency_ms: %{
        p50: percentile(counters, count, 0.50),
        p95: percentile(counters, count, 0.95),
        p99: percentile(counters, count, 0.99),
        max: Float.round(:counters.get(counters, @buckets + 2) / 1000, 1)
      },
      vm: %{
        processes: :erlang.system_info(:process_count),
        run_queue: :erlang.statistics(:total_run_queue_lengths_all),
        memory_mb: div(:erlang.memory(:total), 1_048_576),
        schedulers: :erlang.system_info(:schedulers_online),
        node: node(),
        cluster: Node.list()
      }
    }
  end

  defp bucket(latency_us) when latency_us <= 1, do: 1

  defp bucket(latency_us),
    do: min(trunc(:math.log(latency_us) / :math.log(@growth)) + 1, @buckets)

  defp percentile(_counters, 0, _p), do: nil

  defp percentile(counters, count, p) do
    target = Float.ceil(count * p)

    Enum.reduce_while(1..@buckets, 0, fn index, seen ->
      seen = seen + :counters.get(counters, index)
      if seen >= target, do: {:halt, {:found, index}}, else: {:cont, seen}
    end)
    |> case do
      {:found, index} -> Float.round(:math.pow(@growth, index) / 1000, 1)
      _ -> nil
    end
  end
end
