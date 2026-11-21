defmodule Minion.AI.StubClient do
  def generate(_prompt) do
    Application.get_env(:minion, :ai_stub_response) || {:ok, "stub summary"}
  end
end
