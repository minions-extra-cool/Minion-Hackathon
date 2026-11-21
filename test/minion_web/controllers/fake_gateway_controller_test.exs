defmodule MinionWeb.FakeGatewayControllerTest do
  use MinionWeb.ConnCase

  alias Minion.FakeGateway

  setup do
    FakeGateway.set_down(false)
    FakeGateway.clear()
    on_exit(fn -> FakeGateway.set_down(false) end)
  end

  test "accepts an SMS", %{conn: conn} do
    conn =
      post(conn, ~p"/fake-gateway/messages", %{channel: "sms", to: "+48100", text: "Disk full"})

    assert %{"id" => _} = json_response(conn, 200)
    assert [%{channel: "sms", to: "+48100", text: "Disk full"}] = FakeGateway.messages()
  end

  test "answers 503 while the gateway is down", %{conn: conn} do
    FakeGateway.set_down(true)

    conn =
      post(conn, ~p"/fake-gateway/messages", %{channel: "sms", to: "+48100", text: "Disk full"})

    assert %{"error" => "gateway is down"} = json_response(conn, 503)
  end

  test "answers 422 for an invalid message", %{conn: conn} do
    conn = post(conn, ~p"/fake-gateway/messages", %{channel: "fax", to: "+48100", text: "hi"})

    assert json_response(conn, 422)
  end
end
