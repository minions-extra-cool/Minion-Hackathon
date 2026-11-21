defmodule Minion.Alerts.Pipeline do
  use Broadway

  require Logger

  alias Broadway.Message
  alias Minion.Alerts.Processor
  alias Minion.Kafka
  alias Minion.Rules.Cache

  @producers 6
  @poll_interval_ms 10
  @max_attempts 5
  @max_backoff_ms 5_000

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {BroadwayKafka.Producer,
           hosts: Kafka.brokers(),
           group_id: "minion-pipeline",
           topics: [Kafka.events_topic()],
           offset_reset_policy: :earliest,
           receive_interval: @poll_interval_ms,
           fetch_config: [max_wait_time: @poll_interval_ms]},
        concurrency: @producers
      ],
      processors: [default: [concurrency: System.schedulers_online()]]
    )
  end

  @impl true
  def handle_message(_processor, message, _context) do
    with {:ok, envelope} <- Jason.decode(message.data),
         {:ok, outcomes} <- process(envelope, 1) do
      if outcomes == [], do: Logger.debug("No rule matched event #{envelope["id"]}")
      record_latency(envelope)
      message
    else
      {:error, reason} -> Message.failed(message, reason)
    end
  end

  defp record_latency(%{"received_at" => received_at}) when is_binary(received_at) do
    case DateTime.from_iso8601(received_at) do
      {:ok, at, _offset} ->
        Minion.Metrics.record(max(DateTime.diff(DateTime.utc_now(), at, :microsecond), 0))

      _ ->
        :ok
    end
  end

  defp record_latency(_envelope), do: :ok

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, &dead_letter/1)
    messages
  end

  defp process(envelope, attempt) do
    case process_once(envelope) do
      {:ok, outcomes} ->
        {:ok, outcomes}

      {:error, %DBConnection.ConnectionError{} = error} ->
        Logger.warning(
          "Database unavailable, retrying event #{envelope["id"]}: #{Exception.message(error)}"
        )

        Process.sleep(backoff(attempt))
        process(envelope, attempt + 1)

      {:error, reason} when attempt < @max_attempts ->
        Logger.warning(
          "Processing event #{envelope["id"]} failed (attempt #{attempt}): #{inspect(reason)}"
        )

        Process.sleep(backoff(attempt))
        process(envelope, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_once(envelope) do
    Processor.process(envelope, Cache.all())
  rescue
    error -> {:error, error}
  end

  defp backoff(attempt), do: min(100 * Integer.pow(2, attempt), @max_backoff_ms)

  defp dead_letter(%Message{data: data, status: {_kind, reason, _stacktrace}} = message),
    do: dead_letter(message, data, reason)

  defp dead_letter(%Message{data: data, status: {:failed, reason}} = message),
    do: dead_letter(message, data, reason)

  defp dead_letter(message, data, reason) do
    key = to_string(message.metadata[:key] || "")
    headers = [{"error", inspect(reason, limit: 50)}]

    case Kafka.produce(Kafka.dead_letter_topic(), key, [
           %{key: key, value: data, headers: headers}
         ]) do
      {:ok, _position} ->
        Logger.error(
          "Event moved to #{Kafka.dead_letter_topic()} after failing: #{inspect(reason)}"
        )

      {:error, produce_error} ->
        Logger.error(
          "Event failed and could not be dead-lettered (#{inspect(produce_error)}): #{data}"
        )
    end
  end
end
