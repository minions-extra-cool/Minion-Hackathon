defmodule Minion.Ingest.KafkaSourceTest do
  use ExUnit.Case, async: true

  alias Broadway.Message
  alias Minion.Ingest.KafkaSource

  defp kafka_message(topic, data) do
    %Message{
      data: data,
      metadata: %{topic: topic, partition: 0, offset: 7, key: ""},
      acknowledger: Broadway.NoopAcknowledger.init()
    }
  end

  defp envelope(topic, data) do
    KafkaSource.handle_message(:default, kafka_message(topic, data), %{}).data
  end

  test "wraps a JSON message in an envelope named after its configured source" do
    data =
      ~s({"type":"WORKFLOW_FAILED","workflowName":"Order-settlement","error":{"code":"TIMEOUT"}})

    assert %{
             "source" => "workflow-engine",
             "source_type" => "kafka",
             "payload" => %{
               "type" => "WORKFLOW_FAILED",
               "workflowName" => "Order-settlement",
               "error" => %{"code" => "TIMEOUT"}
             }
           } = envelope("workflow-events", data)
  end

  test "keeps a message that is not JSON as a raw string" do
    assert %{"payload" => "2026-11-21 WARN pricing-engine-3 latency 1200ms"} =
             envelope("workflow-events", "2026-11-21 WARN pricing-engine-3 latency 1200ms")
  end

  for codec <- [:gzip, :snappy, :lz4] do
    test "can read #{codec}-compressed batches from external producers" do
      data = ~s({"type":"WORKFLOW_FAILED"})
      compressed = unquote(codec) |> :kpro_compress.compress(data) |> IO.iodata_to_binary()

      decompressed =
        unquote(codec) |> :kpro_compress.decompress(compressed) |> IO.iodata_to_binary()

      assert decompressed == data
    end
  end

  test "a topic missing from the config uses the topic name as the source" do
    assert KafkaSource.source_for("workflow-events") == "workflow-engine"
    assert KafkaSource.source_for("unlisted-topic") == "unlisted-topic"
  end
end
