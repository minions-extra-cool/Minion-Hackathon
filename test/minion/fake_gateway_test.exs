defmodule Minion.FakeGatewayTest do
  use ExUnit.Case

  alias Minion.FakeGateway

  setup do
    FakeGateway.set_down(false)
    FakeGateway.clear()
    on_exit(fn -> FakeGateway.set_down(false) end)
  end

  test "keeps received messages, newest first, and tells subscribers" do
    FakeGateway.subscribe()

    {:ok, _} =
      FakeGateway.receive_message(%{"channel" => "sms", "to" => "+48100", "text" => "first"})

    {:ok, _} =
      FakeGateway.receive_message(%{"channel" => "phone", "to" => "+48200", "text" => "second"})

    assert [%{text: "second", channel: "phone"}, %{text: "first", channel: "sms"}] =
             FakeGateway.messages()

    assert_received {:gateway_message, %{text: "first"}}
    assert_received {:gateway_message, %{text: "second"}}
  end

  test "refuses messages while down" do
    FakeGateway.set_down(true)

    assert {:error, :down} =
             FakeGateway.receive_message(%{"channel" => "sms", "to" => "+48100", "text" => "hi"})

    assert FakeGateway.messages() == []
  end

  test "rejects messages that are not an SMS or call with a recipient and text" do
    assert {:error, :invalid_message} =
             FakeGateway.receive_message(%{"channel" => "fax", "to" => "+48100", "text" => "hi"})

    assert {:error, :invalid_message} =
             FakeGateway.receive_message(%{"channel" => "sms", "to" => "", "text" => "hi"})
  end
end
