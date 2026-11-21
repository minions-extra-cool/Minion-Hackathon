defmodule Minion.KafkaHelpers do
  require Record

  Record.defrecordp(
    :kafka_message,
    Record.extract(:kafka_message, from_lib: "brod/include/brod.hrl")
  )

  def read_messages(%{partition: partition, offset: offset}, count) do
    {:ok, {_high_watermark, messages}} =
      :brod.fetch(Minion.Kafka.brokers(), Minion.Kafka.events_topic(), partition, offset)

    messages
    |> Enum.take(count)
    |> Enum.map(&Jason.decode!(kafka_message(&1, :value)))
  end
end
