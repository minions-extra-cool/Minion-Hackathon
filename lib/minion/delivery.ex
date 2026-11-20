defmodule Minion.Delivery do
  require Logger

  alias Minion.Alerts.Alert

  @spec dispatch(Alert.t()) :: :ok
  def dispatch(%Alert{} = alert) do
    Logger.info("dispatch stub: alert #{alert.id} (#{alert.severity}) #{alert.title}")
    :ok
  end
end
