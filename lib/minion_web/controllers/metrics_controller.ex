defmodule MinionWeb.MetricsController do
  use MinionWeb, :controller

  def show(conn, _params), do: json(conn, Minion.Metrics.snapshot())

  def reset(conn, _params) do
    Minion.Metrics.reset()
    json(conn, Minion.Metrics.snapshot())
  end
end
