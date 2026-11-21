defmodule Minion.Kafka.Topics do
  require Logger

  alias Minion.Kafka

  @attempts 15
  @retry_delay_ms 1_000

  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :temporary}
  end

  def start_link do
    ensure(Kafka.events_topic(), Kafka.config(:events_partitions))
    :ignore
  end

  def ensure(topic, partitions, attempt \\ 1) do
    case :brod.get_partitions_count_safe(Kafka.client(), topic) do
      {:ok, count} when count < partitions ->
        Logger.warning(
          "Kafka topic #{topic} has #{count} partitions, fewer than the configured #{partitions}"
        )

        :ok

      {:ok, _count} ->
        :ok

      {:error, reason} when attempt >= @attempts ->
        Logger.error("Kafka topic #{topic} is not available: #{inspect(reason)}")
        {:error, reason}

      {:error, _reason} ->
        create(topic, partitions)
        Process.sleep(@retry_delay_ms)
        ensure(topic, partitions, attempt + 1)
    end
  end

  defp create(topic, partitions) do
    config = %{
      name: topic,
      num_partitions: partitions,
      replication_factor: 1,
      assignments: [],
      configs: []
    }

    :brod.create_topics(Kafka.brokers(), [config], %{timeout: 5_000})
  end
end
