defmodule Minion.Rules.Path do
  @spec fetch(term(), String.t()) :: {:ok, term()} | :error
  def fetch(data, path) when is_binary(path) do
    path
    |> String.split(".")
    |> Enum.reduce_while({:ok, data}, fn segment, {:ok, current} ->
      case step(current, segment) do
        {:ok, next} -> {:cont, {:ok, next}}
        :error -> {:halt, :error}
      end
    end)
  end

  @spec get(term(), String.t()) :: term()
  def get(data, path) do
    case fetch(data, path) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp step(map, segment) when is_map(map), do: Map.fetch(map, segment)

  defp step(list, segment) when is_list(list) do
    case Integer.parse(segment) do
      {index, ""} when index >= 0 -> Enum.fetch(list, index)
      _ -> :error
    end
  end

  defp step(_other, _segment), do: :error
end
