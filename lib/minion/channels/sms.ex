defmodule Minion.Channels.Sms do
  @behaviour Minion.Channel

  alias Minion.Accounts.Person
  alias Minion.Alerts.Alert
  alias Minion.Channels.Gateway

  @impl Minion.Channel
  def deliver(%Alert{}, %Person{phone: phone}) when phone in [nil, ""],
    do: {:error, :no_phone_number}

  def deliver(%Alert{} = alert, %Person{phone: phone}) do
    Gateway.send_message(
      "sms",
      phone,
      "[#{String.upcase(to_string(alert.severity))}] #{alert.title}"
    )
  end
end
