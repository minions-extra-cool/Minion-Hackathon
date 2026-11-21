defmodule Minion.Ingest do
  alias Minion.Kafka

  @produce_timeout_ms 5_000

  @type envelope :: %{String.t() => term()}

  @spec envelope(String.t(), String.t(), term()) :: envelope()
  def envelope(source, source_type, payload) do
    %{
      "id" => Ecto.UUID.generate(),
      "source" => source,
      "source_type" => source_type,
      "received_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "payload" => payload
    }
  end

  @spec decode(binary()) :: term()
  def decode(raw) do
    case Jason.decode(raw) do
      {:ok, value} -> value
      {:error, _} -> raw
    end
  end

  @spec publish(envelope() | [envelope(), ...]) ::
          {:ok, %{partition: non_neg_integer(), offset: non_neg_integer()}} | {:error, term()}
  def publish(%{} = envelope), do: publish([envelope])

  def publish([%{"id" => key} | _] = envelopes) do
    topic = Kafka.events_topic()
    messages = Enum.map(envelopes, &%{key: &1["id"], value: Jason.encode!(&1)})

    with {:ok, partitions} <- :brod.get_partitions_count_safe(Kafka.client(), topic),
         partition = :erlang.phash2(key, partitions),
         {:ok, call_ref} <- :brod.produce(Kafka.client(), topic, partition, key, messages),
         {:ok, offset} <- :brod.sync_produce_request_offset(call_ref, @produce_timeout_ms) do
      {:ok, %{partition: partition, offset: offset}}
    end
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end
end
