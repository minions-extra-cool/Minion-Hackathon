defmodule MinionWeb.FakeGatewayController do
  use MinionWeb, :controller

  alias Minion.FakeGateway

  def create(conn, params) do
    case FakeGateway.receive_message(params) do
      {:ok, message} ->
        json(conn, %{id: message.id})

      {:error, :down} ->
        conn |> put_status(503) |> json(%{error: "gateway is down"})

      {:error, :invalid_message} ->
        conn
        |> put_status(422)
        |> json(%{error: ~s(expected {"channel": "sms" | "phone", "to": "...", "text": "..."})})
    end
  end
end
