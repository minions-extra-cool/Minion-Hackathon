defmodule MinionWeb.SessionControllerTest do
  use MinionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Minion.AlertFixtures

  setup do
    team = team_fixture()
    %{anna: person_fixture(team, "Anna"), piotr: person_fixture(team, "Piotr")}
  end

  test "picking a person remembers them and returns to the page you were on", %{
    conn: conn,
    anna: anna
  } do
    conn =
      conn
      |> put_req_header("referer", "http://localhost/rules?x=1")
      |> post(~p"/session/person?#{[person_id: anna.id]}")

    assert redirected_to(conn) == "/rules?x=1"
    assert get_session(conn, "person_id") == anna.id

    {:ok, view, _html} = conn |> recycle() |> live(~p"/")
    assert has_element?(view, "#current-person-name", "Anna")
  end

  test "the top bar offers everyone else to switch to", %{conn: conn, anna: anna, piotr: piotr} do
    {:ok, view, _html} =
      conn |> Plug.Test.init_test_session(%{"person_id" => anna.id}) |> live(~p"/")

    assert has_element?(view, "#act-as-#{piotr.id}", "Piotr")
    refute has_element?(view, "#act-as-#{anna.id}")
  end

  test "nobody is picked until you choose", %{conn: conn, anna: anna} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#person-menu-button", "Who are you?")
    assert has_element?(view, "#act-as-#{anna.id}")
  end

  test "an outside referer is not followed", %{conn: conn, anna: anna} do
    conn =
      conn
      |> put_req_header("referer", "http://localhost//evil.example/phish")
      |> post(~p"/session/person?#{[person_id: anna.id]}")

    assert redirected_to(conn) == "/"
  end

  test "an unknown person is refused", %{conn: conn} do
    conn = post(conn, ~p"/session/person?#{[person_id: Ecto.UUID.generate()]}")

    assert redirected_to(conn) == "/"
    assert get_session(conn, "person_id") == nil
  end
end
