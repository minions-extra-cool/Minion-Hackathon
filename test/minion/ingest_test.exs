defmodule Minion.IngestTest do
  use ExUnit.Case, async: true

  import Minion.KafkaHelpers

  alias Minion.Ingest

  describe "envelope/3" do
    test "wraps the payload untouched with our own fields" do
      payload = %{"type" => "DISK_FULL", "host" => "web-1"}

      envelope = Ingest.envelope("ops-monitor", "http", payload)

      assert %{"source" => "ops-monitor", "source_type" => "http", "payload" => ^payload} =
               envelope

      assert {:ok, _} = Ecto.UUID.cast(envelope["id"])
      assert {:ok, _, 0} = DateTime.from_iso8601(envelope["received_at"])
    end
  end

  describe "decode/1" do
    test "returns parsed JSON" do
      assert Ingest.decode(~s({"a": {"b": 1}})) == %{"a" => %{"b" => 1}}
      assert Ingest.decode(~s([1, 2])) == [1, 2]
    end

    test "keeps anything that is not JSON as the raw string" do
      assert Ingest.decode("2026-11-20 WARN pricing-engine-3 latency 1200ms") ==
               "2026-11-20 WARN pricing-engine-3 latency 1200ms"
    end
  end

  describe "publish/1" do
    test "appends envelopes to the events topic in order" do
      first = Ingest.envelope("test", "http", %{"n" => 1})
      second = Ingest.envelope("test", "http", "plain text")

      assert {:ok, position} = Ingest.publish([first, second])
      assert read_messages(position, 2) == [first, second]
    end

    test "accepts a single envelope" do
      envelope = Ingest.envelope("test", "http", %{"n" => 1})

      assert {:ok, position} = Ingest.publish(envelope)
      assert read_messages(position, 1) == [envelope]
    end
  end
end
