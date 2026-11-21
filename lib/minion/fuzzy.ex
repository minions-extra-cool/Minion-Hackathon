defmodule Minion.Fuzzy do
  @spec match?(String.t() | nil, String.t()) :: boolean()
  def match?(query, text) when query in [nil, ""], do: is_binary(text)

  def match?(query, text) do
    words = text |> normalize() |> String.split(~r/\s+/, trim: true)

    query
    |> normalize()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.all?(fn term -> Enum.any?(words, &in_order?(term, &1)) end)
  end

  defp in_order?(term, haystack) do
    term
    |> String.graphemes()
    |> Enum.reduce_while(0, fn char, from ->
      case :binary.match(haystack, char, scope: {from, byte_size(haystack) - from}) do
        {position, length} -> {:cont, position + length}
        :nomatch -> {:halt, :nomatch}
      end
    end)
    |> Kernel.!=(:nomatch)
  end

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace("ł", "l")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end
end
