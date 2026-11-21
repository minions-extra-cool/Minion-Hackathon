defmodule Minion.Rules.Fingerprint do
  alias Minion.Rules.Path

  @spec compute(%{id: String.t(), dedup: map()}, map()) :: String.t()
  def compute(%{id: rule_id, dedup: dedup}, envelope) do
    values = dedup |> Map.get("key", []) |> Enum.map(&Path.get(envelope, &1))

    :crypto.hash(:sha256, Jason.encode!([rule_id | values]))
    |> Base.encode16(case: :lower)
  end
end
