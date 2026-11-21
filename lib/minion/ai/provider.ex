defmodule Minion.AI.Provider do
  @type option :: {:json, boolean()} | {:max_output_tokens, pos_integer()}

  @callback generate(prompt :: String.t(), [option()]) :: {:ok, String.t()} | {:error, term()}
end
