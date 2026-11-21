defmodule Minion.Ingest do
  alias Minion.Kafka

  @type envelope :: %{String.t() => term()}

  @spec envelope(String.t(), String.t(), term(), keyword()) :: envelope()
  def envelope(source, source_type, payload, opts \\ []) do
    %{
      "id" => Ecto.UUID.generate(),
      "source" => source,
      "source_type" => source_type,
      "received_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "payload" => payload
    }
    |> then(&if(team = opts[:team], do: Map.put(&1, "team", team), else: &1))
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
    messages = Enum.map(envelopes, &%{key: &1["id"], value: Jason.encode!(&1)})
    Kafka.produce(Kafka.events_topic(), key, messages)
  end
end
