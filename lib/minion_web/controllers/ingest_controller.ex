defmodule MinionWeb.IngestController do
  use MinionWeb, :controller

  alias Minion.{Accounts, Ingest}

  @max_body_bytes 1_000_000

  def create(conn, %{"source" => source}) do
    case conn |> bearer_token() |> authenticate() do
      {:ok, team} -> read_and_publish(conn, source, team)
      {:error, message} -> unauthorized(conn, message)
    end
  end

  defp bearer_token(conn) do
    Enum.find_value(get_req_header(conn, "authorization"), fn header ->
      case String.split(header, " ", parts: 2) do
        [scheme, key] -> if String.downcase(scheme) == "bearer", do: String.trim(key)
        _ -> nil
      end
    end)
  end

  defp authenticate(key) when key in [nil, ""],
    do: {:error, "missing team key: send it as Authorization: Bearer <key>"}

  defp authenticate(key) do
    case Accounts.team_for_ingest_key(key) do
      nil -> {:error, "unknown team key"}
      team -> {:ok, team}
    end
  end

  defp read_and_publish(conn, source, team) do
    case Plug.Conn.read_body(conn, length: @max_body_bytes) do
      {:ok, "", conn} ->
        error(conn, 400, "empty body")

      {:ok, body, conn} ->
        body
        |> Ingest.decode()
        |> List.wrap()
        |> Enum.map(&Ingest.envelope(source, "http", &1, team: team.name))
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

  defp unauthorized(conn, message) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer realm="minion ingest"))
    |> error(401, message)
  end

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
