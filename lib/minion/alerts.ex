defmodule Minion.Alerts do
  alias Minion.Alerts.Alert

  @spec topic(Alert.t()) :: String.t()
  def topic(%Alert{owner_type: owner_type, owner_id: owner_id}),
    do: "alerts:#{owner_type}:#{owner_id}"
end
