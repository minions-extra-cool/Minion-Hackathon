defmodule MinionWeb.IngestController do
  use MinionWeb, :controller

  alias Minion.Ingest

  @max_body_bytes 1_000_000

  def create(conn, %{"source" => source}) do
    case Plug.Conn.read_body(conn, length: @max_body_bytes) do
      {:ok, "", conn} ->
        error(conn, 400, "empty body")

      {:ok, body, conn} ->
        body
        |> Ingest.decode()
        |> List.wrap()
        |> Enum.map(&Ingest.envelope(source, "http", &1))
        |> accept(conn)

      {:more, _partial, conn} ->
        error(conn, 413, "body larger than #{@max_body_bytes} bytes")
    end
  end

  defp accept([], conn), do: conn |> put_status(202) |> json(%{accepted: 0, ids: []})

  defp accept(envelopes, conn) do
    case Ingest.publish(envelopes) do
      {:ok, _position} ->
        conn
        |> put_status(202)
        |> json(%{accepted: length(envelopes), ids: Enum.map(envelopes, & &1["id"])})

      {:error, _reason} ->
        error(conn, 503, "event bus unavailable, retry later")
    end
  end

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
