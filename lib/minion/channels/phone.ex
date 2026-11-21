defmodule Minion.Channels.Phone do
  @behaviour Minion.Channel

  alias Minion.Accounts.Person
  alias Minion.Alerts.Alert
  alias Minion.Channels.Gateway

  @impl Minion.Channel
  def label, do: "Phone call"

  @impl Minion.Channel
  def permanent_errors, do: [:no_phone_number]

  @impl Minion.Channel
  def deliver(%Alert{}, %Person{phone: phone}) when phone in [nil, ""],
    do: {:error, :no_phone_number}

  def deliver(%Alert{} = alert, %Person{phone: phone}) do
    Gateway.send_message(
      "phone",
      phone,
      "This is Minion with a #{alert.severity} alert: #{alert.title}. Details are in the Minion app."
    )
  end
end
