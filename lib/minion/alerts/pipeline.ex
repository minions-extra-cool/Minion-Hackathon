defmodule Minion.Alerts.Pipeline do
  use Broadway

  require Logger

  alias Broadway.Message
  alias Minion.Alerts.Processor
  alias Minion.Kafka
  alias Minion.Rules.Cache

  @producers 6
  @poll_interval_ms 10
  @batch_timeout_ms 10
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
      processors: [default: [concurrency: processors()]],
      batchers: [
        default: [
          concurrency: batchers(),
          batch_size: batch_size(),
          batch_timeout: @batch_timeout_ms
        ]
      ]
    )
  end

  def processors, do: setting(:processors, System.schedulers_online())
  def batchers, do: setting(:batchers, 8)
  def batch_size, do: setting(:batch_size, 500)

  defp setting(key, default), do: Application.get_env(:minion, :pipeline)[key] || default

  @impl true
  def handle_message(_processor, message, _context) do
    case Jason.decode(message.data) do
      {:ok, envelope} ->
        candidates = Processor.candidates(envelope, Cache.all())
        if candidates == [], do: Logger.debug("No rule matched event #{envelope["id"]}")

        message
        |> Message.put_data({envelope, candidates})
        |> Message.put_batch_key(batch_key(candidates))

      {:error, reason} ->
        Message.failed(message, reason)
    end
  end

  defp batch_key([]), do: :unmatched
  defp batch_key([%{fingerprint: fingerprint} | _]), do: :erlang.phash2(fingerprint, batchers())

  @impl true
  def handle_batch(:default, messages, %{batch_key: :unmatched}, _context),
    do: Enum.map(messages, &process_alone/1)

  def handle_batch(:default, messages, _batch_info, _context) do
    candidates =
      Enum.flat_map(messages, fn %Message{data: {_envelope, candidates}} -> candidates end)

    case process_batch(candidates, 1) do
      {:ok, _outcomes} ->
        Enum.each(messages, fn %Message{data: {envelope, _}} -> record_latency(envelope) end)
        messages

      {:error, reason} ->
        Logger.warning(
          "Batch of #{length(messages)} events failed (#{inspect(reason)}), processing them one by one"
        )

        Enum.map(messages, &process_alone/1)
    end
  end

  defp process_batch(candidates, attempt) do
    case safely(fn -> Processor.process_batch(candidates) end) do
      {:error, %DBConnection.ConnectionError{} = error} ->
        Logger.warning("Database unavailable, retrying batch: #{Exception.message(error)}")
        Process.sleep(backoff(attempt))
        process_batch(candidates, attempt + 1)

      result ->
        result
    end
  end

  defp process_alone(%Message{data: {envelope, _candidates}} = message) do
    case process(envelope, 1) do
      {:ok, _outcomes} ->
        record_latency(envelope)
        message

      {:error, reason} ->
        Message.failed(message, reason)
    end
  end

  defp process(envelope, attempt) do
    case safely(fn -> Processor.process(envelope, Cache.all()) end) do
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

  defp safely(fun) do
    fun.()
  rescue
    error -> {:error, error}
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

  defp backoff(attempt), do: min(100 * Integer.pow(2, attempt), @max_backoff_ms)

  defp dead_letter(%Message{status: {_kind, reason, _stacktrace}} = message),
    do: dead_letter(message, reason)

  defp dead_letter(%Message{status: {:failed, reason}} = message),
    do: dead_letter(message, reason)

  defp dead_letter(%Message{data: data} = message, reason) do
    key = to_string(message.metadata[:key] || "")
    value = original_value(data)
    headers = [{"error", inspect(reason, limit: 50)}]

    case Kafka.produce(Kafka.dead_letter_topic(), key, [
           %{key: key, value: value, headers: headers}
         ]) do
      {:ok, _position} ->
        Logger.error(
          "Event moved to #{Kafka.dead_letter_topic()} after failing: #{inspect(reason)}"
        )

      {:error, produce_error} ->
        Logger.error(
          "Event failed and could not be dead-lettered (#{inspect(produce_error)}): #{value}"
        )
    end
  end

  defp original_value({envelope, _candidates}), do: Jason.encode!(envelope)
  defp original_value(raw) when is_binary(raw), do: raw
end
