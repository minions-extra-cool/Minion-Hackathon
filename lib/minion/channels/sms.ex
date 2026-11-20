defmodule Minion.Channels.Sms do
  @moduledoc false

  @behaviour Minion.Channel

  alias Minion.Accounts.Person
  alias Minion.Alerts.Alert

  @impl Minion.Channel
  def deliver(%Alert{}, %Person{}) do
    {:error, :not_implemented}
  end
end
