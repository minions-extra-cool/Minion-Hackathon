defmodule MinionWeb.IngestControllerTest do
  use MinionWeb.ConnCase, async: true

  import Minion.AlertFixtures

  alias Minion.Accounts

  setup do
    {:ok, team, key} = Accounts.generate_ingest_key(team_fixture())
    %{team: team, key: key}
  end

  defp post_raw(conn, body, key) do
    conn
    |> put_req_header("authorization", "Bearer #{key}")
    |> put_req_header("content-type", "application/json")
    |> post(~p"/ingest/ops-monitor", body)
  end

  describe "with the team's key" do
    test "accepts a JSON object as one event", %{conn: conn, key: key} do
      conn = post_raw(conn, ~s({"type":"DISK_FULL","host":"web-1"}), key)

      assert %{"accepted" => 1, "ids" => [id]} = json_response(conn, 202)
      assert {:ok, _} = Ecto.UUID.cast(id)
    end

    test "accepts a JSON array as several events", %{conn: conn, key: key} do
      conn = post_raw(conn, ~s([{"host":"web-1"},{"host":"web-2"}]), key)

      assert %{"accepted" => 2, "ids" => [_, _]} = json_response(conn, 202)
    end

    test "accepts a body that is not JSON, even when labelled as JSON", %{conn: conn, key: key} do
      conn = post_raw(conn, "WARN pricing-engine-3 latency 1200ms", key)

      assert %{"accepted" => 1} = json_response(conn, 202)
    end

    test "accepts an empty JSON array without publishing anything", %{conn: conn, key: key} do
      conn = post_raw(conn, "[]", key)

      assert %{"accepted" => 0, "ids" => []} = json_response(conn, 202)
    end

    test "rejects an empty body", %{conn: conn, key: key} do
      conn = post_raw(conn, "", key)

      assert %{"error" => "empty body"} = json_response(conn, 400)
    end

    test "the key can also come as X-Minion-Key or ?key=", %{conn: conn, key: key} do
      by_header =
        conn
        |> put_req_header("x-minion-key", key)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/ingest/ops-monitor", ~s({"a":1}))

      assert %{"accepted" => 1} = json_response(by_header, 202)

      by_query =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/ingest/ops-monitor?#{[key: key]}", ~s({"a":1}))

      assert %{"accepted" => 1} = json_response(by_query, 202)
    end
  end

  describe "without a valid key" do
    test "a post without a key is refused with 401 and a hint", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/ingest/ops-monitor", ~s({"a":1}))

      assert %{"error" => "missing team key" <> _} = json_response(conn, 401)
      assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="minion ingest")]
    end

    test "a wrong key is refused with 401", %{conn: conn} do
      conn = post_raw(conn, ~s({"a":1}), "mk_not-a-real-key-at-all")

      assert %{"error" => "unknown team key"} = json_response(conn, 401)
    end

    test "a rotated key stops working at once", %{conn: conn, team: team, key: old_key} do
      {:ok, _team, new_key} = Accounts.generate_ingest_key(team)

      assert json_response(post_raw(conn, ~s({"a":1}), old_key), 401)
      assert json_response(post_raw(build_conn(), ~s({"a":1}), new_key), 202)
    end
  end

  test "the key is stored only as a hash", %{team: team, key: key} do
    stored = Accounts.get_team!(team.id)

    refute stored.ingest_key_hash == key
    assert stored.ingest_key_hint == String.slice(key, -4, 4)
    refute inspect(stored) =~ key
    assert Accounts.team_for_ingest_key(key).id == team.id
  end
end
