defmodule MinionWeb.CurrentPerson do
  import Phoenix.Component, only: [assign: 3]

  alias Minion.Accounts

  @session_key "person_id"

  def session_key, do: @session_key

  def on_mount(:default, _params, session, socket) do
    {:cont,
     socket
     |> assign(:current_person, Accounts.get_person(session[@session_key]))
     |> assign(:people, Accounts.list_people())}
  end
end
