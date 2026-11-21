defmodule Minion.Rules.Template do
  alias Minion.Rules.Path

  @placeholder ~r/\{\{\s*([^{}\s]+)\s*\}\}/

  @spec render(String.t() | nil, map()) :: String.t()
  def render(nil, _envelope), do: ""

  def render(template, envelope) when is_binary(template) do
    Regex.replace(@placeholder, template, fn _placeholder, path ->
      envelope |> Path.get(path) |> to_text()
    end)
  end

  defp to_text(nil), do: ""
  defp to_text(value) when is_binary(value), do: value
  defp to_text(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp to_text(value), do: Jason.encode!(value)
end
