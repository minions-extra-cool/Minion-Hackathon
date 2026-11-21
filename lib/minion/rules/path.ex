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

  @spec list(term()) :: [String.t()]
  def list(data), do: data |> list("") |> Enum.sort()

  defp list(map, prefix) when is_map(map) and map_size(map) > 0 do
    Enum.flat_map(map, fn {key, value} -> list(value, join(prefix, to_string(key))) end)
  end

  defp list([first | _rest], prefix), do: list(first, join(prefix, "0"))
  defp list(_leaf, ""), do: []
  defp list(_leaf, prefix), do: [prefix]

  defp join("", segment), do: segment
  defp join(prefix, segment), do: prefix <> "." <> segment

  defp step(map, segment) when is_map(map), do: Map.fetch(map, segment)

  defp step(list, segment) when is_list(list) do
    case Integer.parse(segment) do
      {index, ""} when index >= 0 -> Enum.fetch(list, index)
      _ -> :error
    end
  end

  defp step(_other, _segment), do: :error
end
