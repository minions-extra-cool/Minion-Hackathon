defmodule Minion.Kafka do
  use GenServer

  require Logger

  @client :minion_kafka
  @restart_delay_ms 1_000

  def client, do: @client

  def brokers, do: config(:brokers)

  def events_topic, do: config(:events_topic)

  def dead_letter_topic, do: config(:dead_letter_topic)

  def config(key), do: :minion |> Application.fetch_env!(:kafka) |> Keyword.fetch!(key)

  @produce_timeout_ms 5_000

  @spec produce(String.t(), String.t(), [map(), ...]) ::
          {:ok, %{partition: non_neg_integer(), offset: non_neg_integer()}} | {:error, term()}
  def produce(topic, key, messages) do
    with {:ok, partitions} <- :brod.get_partitions_count_safe(@client, topic),
         partition = :erlang.phash2(key, partitions),
         {:ok, call_ref} <- :brod.produce(@client, topic, partition, key, messages),
         {:ok, offset} <- :brod.sync_produce_request_offset(call_ref, @produce_timeout_ms) do
      {:ok, %{partition: partition, offset: offset}}
    end
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, start_client()}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, pid) do
    Logger.warning(
      "Kafka client stopped (#{inspect(reason)}), restarting in #{@restart_delay_ms}ms"
    )

    Process.send_after(self(), :restart_client, @restart_delay_ms)
    {:noreply, nil}
  end

  def handle_info({:EXIT, _pid, _reason}, client_pid), do: {:noreply, client_pid}

  def handle_info(:restart_client, nil), do: {:noreply, start_client()}

  @impl true
  def terminate(_reason, _client_pid), do: :brod.stop_client(@client)

  defp start_client do
    client_config = [
      auto_start_producers: true,
      allow_topic_auto_creation: false,
      unknown_topic_cache_ttl: 500,
      default_producer_config: []
    ]

    case :brod.start_link_client(brokers(), @client, client_config) do
      {:ok, pid} ->
        pid

      {:error, reason} ->
        Logger.warning("Kafka client failed to start (#{inspect(reason)}), retrying")
        Process.send_after(self(), :restart_client, @restart_delay_ms)
        nil
    end
  end
end
