defmodule MinionWeb.PageController do
  use MinionWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
