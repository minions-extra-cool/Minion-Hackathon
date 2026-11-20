defmodule Minion.Channel do
  alias Minion.Accounts.Person
  alias Minion.Alerts.Alert

  @callback deliver(Alert.t(), Person.t()) :: :ok | {:error, term()}
end
