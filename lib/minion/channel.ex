defmodule Minion.Channel do
  alias Minion.Accounts.Person
  alias Minion.Alerts.Alert

  @callback label() :: String.t()
  @callback deliver(Alert.t(), Person.t()) :: :ok | {:error, term()}
  @callback permanent_errors() :: [term()]

  @optional_callbacks permanent_errors: 0
end
