defmodule MinionWeb.SessionController do
  use MinionWeb, :controller

  alias Minion.Accounts
  alias MinionWeb.CurrentPerson

  def create(conn, %{"person_id" => person_id}) do
    case Accounts.get_person(person_id) do
      nil ->
        conn |> put_flash(:error, "That person no longer exists.") |> redirect(to: back(conn))

      person ->
        conn
        |> put_session(CurrentPerson.session_key(), person.id)
        |> put_flash(:info, "You are now acting as #{person.name}.")
        |> redirect(to: back(conn))
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(CurrentPerson.session_key())
    |> redirect(to: back(conn))
  end

  defp back(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{path: path, query: query} when is_binary(path) <- URI.parse(referer),
         true <- local_path?(path) do
      if query, do: "#{path}?#{query}", else: path
    else
      _ -> ~p"/"
    end
  end

  defp local_path?(path),
    do: String.starts_with?(path, "/") and not String.starts_with?(path, "//")
end
