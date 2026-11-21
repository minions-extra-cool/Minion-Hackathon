defmodule Minion.AI do
  @spec client() :: module()
  def client, do: Application.get_env(:minion, :ai_client, Minion.AI.Gemini)
end
