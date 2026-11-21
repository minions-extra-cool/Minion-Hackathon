defmodule Minion.Ingest.KafkaSource do
  use Broadway

  require Logger

  alias Broadway.Message
  alias Minion.{Ingest, Kafka}
  alias Minion.Kafka.Topics

  @producers 2
  @poll_interval_ms 10
  @batch_size 100
  @batch_timeout_ms 10
  @default_partitions 6
  @max_backoff_ms 5_000

  @spec sources() :: [%{topic: String.t(), source: String.t()}]
  def sources, do: Application.fetch_env!(:minion, :kafka_sources)

  def start_link(_opts) do
    topics = Enum.map(sources(), & &1.topic)
    Enum.each(topics, &Topics.ensure(&1, @default_partitions))

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {BroadwayKafka.Producer,
           hosts: Kafka.brokers(),
           group_id: "minion-kafka-sources",
           topics: topics,
           offset_reset_policy: :latest,
           receive_interval: @poll_interval_ms,
           fetch_config: [max_wait_time: @poll_interval_ms]},
        concurrency: @producers
      ],
      processors: [default: [concurrency: System.schedulers_online()]],
      batchers: [default: [batch_size: @batch_size, batch_timeout: @batch_timeout_ms]]
    )
  end

  @impl true
  def handle_message(
        _processor,
        %Message{data: data, metadata: %{topic: topic}} = message,
        _context
      ) do
    Message.put_data(message, Ingest.envelope(source_for(topic), "kafka", Ingest.decode(data)))
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    messages |> Enum.map(& &1.data) |> publish(1)
    messages
  end

  @spec source_for(String.t()) :: String.t()
  def source_for(topic) do
    Enum.find_value(sources(), topic, fn
      %{topic: ^topic, source: source} -> source
      _other -> nil
    end)
  end

  defp publish(envelopes, attempt) do
    case Ingest.publish(envelopes) do
      {:ok, _position} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Publishing #{length(envelopes)} Kafka source events failed (attempt #{attempt}), retrying: #{inspect(reason)}"
        )

        Process.sleep(min(100 * Integer.pow(2, attempt), @max_backoff_ms))
        publish(envelopes, attempt + 1)
    end
  end
end
