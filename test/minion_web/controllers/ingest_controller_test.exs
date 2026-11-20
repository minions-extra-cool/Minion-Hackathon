defmodule MinionWeb.IngestControllerTest do
  use MinionWeb.ConnCase, async: true

  defp post_raw(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/ingest/ops-monitor", body)
  end

  test "accepts a JSON object as one event", %{conn: conn} do
    conn = post_raw(conn, ~s({"type":"DISK_FULL","host":"web-1"}))

    assert %{"accepted" => 1, "ids" => [id]} = json_response(conn, 202)
    assert {:ok, _} = Ecto.UUID.cast(id)
  end

  test "accepts a JSON array as several events", %{conn: conn} do
    conn = post_raw(conn, ~s([{"host":"web-1"},{"host":"web-2"}]))

    assert %{"accepted" => 2, "ids" => [_, _]} = json_response(conn, 202)
  end

  test "accepts a body that is not JSON, even when labelled as JSON", %{conn: conn} do
    conn = post_raw(conn, "WARN pricing-engine-3 latency 1200ms")

    assert %{"accepted" => 1} = json_response(conn, 202)
  end

  test "accepts an empty JSON array without publishing anything", %{conn: conn} do
    conn = post_raw(conn, "[]")

    assert %{"accepted" => 0, "ids" => []} = json_response(conn, 202)
  end

  test "rejects an empty body", %{conn: conn} do
    conn = post_raw(conn, "")

    assert %{"error" => "empty body"} = json_response(conn, 400)
  end
end
