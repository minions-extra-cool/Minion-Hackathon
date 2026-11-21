defmodule Minion.AI.StubClient do
  @behaviour Minion.AI.Provider

  @impl Minion.AI.Provider
  def generate(_prompt, _opts \\ []) do
    Application.get_env(:minion, :ai_stub_response) || {:ok, "stub summary"}
  end
end
