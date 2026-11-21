defmodule MinionWeb.Links do
  use MinionWeb, :verified_routes

  @spec alert_url(Minion.Alerts.Alert.t()) :: String.t()
  def alert_url(alert), do: url(~p"/alerts/#{alert}")
end
