defmodule Minion.Rules.PathTest do
  use ExUnit.Case, async: true

  alias Minion.Rules.Path

  @envelope %{
    "source" => "prometheus",
    "payload" => %{
      "labels" => %{"service" => "payments-api"},
      "errors" => [%{"code" => "TIMEOUT"}, %{"code" => "REJECTED"}],
      "resolved" => nil
    }
  }

  test "walks nested maps" do
    assert Path.fetch(@envelope, "source") == {:ok, "prometheus"}
    assert Path.fetch(@envelope, "payload.labels.service") == {:ok, "payments-api"}
  end

  test "indexes into lists with a number segment" do
    assert Path.fetch(@envelope, "payload.errors.1.code") == {:ok, "REJECTED"}
    assert Path.fetch(@envelope, "payload.errors.5.code") == :error
    assert Path.fetch(@envelope, "payload.errors.first") == :error
  end

  test "tells a missing field apart from a null one" do
    assert Path.fetch(@envelope, "payload.resolved") == {:ok, nil}
    assert Path.fetch(@envelope, "payload.missing") == :error
    assert Path.fetch(@envelope, "payload.labels.service.name") == :error
  end

  test "get returns nil for a missing field" do
    assert Path.get(@envelope, "payload.labels.region") == nil
  end
end
