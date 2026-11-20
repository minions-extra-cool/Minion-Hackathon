defmodule Minion.DeliveryTest do
  use ExUnit.Case, async: true

  alias Minion.Alerts.Alert
  alias Minion.Delivery

  test "dispatch accepts an alert and returns :ok" do
    alert = %Alert{id: Ecto.UUID.generate(), severity: :warning, title: "Disk full on web-1"}

    assert Delivery.dispatch(alert) == :ok
  end
end
