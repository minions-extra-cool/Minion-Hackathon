defmodule Minion.Rules.Matcher do
  alias Minion.Rules.Path

  @spec matches?(map(), map()) :: boolean()
  def matches?(%{"all" => conditions}, envelope) when is_list(conditions),
    do: Enum.all?(conditions, &matches?(&1, envelope))

  def matches?(%{"any" => conditions}, envelope) when is_list(conditions),
    do: Enum.any?(conditions, &matches?(&1, envelope))

  def matches?(%{"field" => field, "op" => op} = condition, envelope) when is_binary(field) do
    case Path.fetch(envelope, field) do
      {:ok, actual} -> compare(op, actual, Map.get(condition, "value"))
      :error -> false
    end
  end

  def matches?(_invalid, _envelope), do: false

  defp compare("exists", actual, _expected), do: actual != nil
  defp compare("eq", actual, expected), do: equal?(actual, expected)
  defp compare("neq", actual, expected), do: not equal?(actual, expected)

  defp compare("in", actual, expected),
    do: expected |> List.wrap() |> Enum.any?(&equal?(actual, &1))

  defp compare("contains", actual, expected), do: contains?(actual, expected)
  defp compare("matches", actual, expected), do: wildcard_match?(actual, expected)
  defp compare("gt", actual, expected), do: numeric(actual, expected, &>/2)
  defp compare("gte", actual, expected), do: numeric(actual, expected, &>=/2)
  defp compare("lt", actual, expected), do: numeric(actual, expected, &</2)
  defp compare("lte", actual, expected), do: numeric(actual, expected, &<=/2)
  defp compare(_unknown_op, _actual, _expected), do: false

  defp equal?(a, b) do
    case {number(a), number(b)} do
      {{:ok, x}, {:ok, y}} -> x == y
      _ -> text(a) == text(b)
    end
  end

  defp numeric(a, b, operator) do
    case {number(a), number(b)} do
      {{:ok, x}, {:ok, y}} -> operator.(x, y)
      _ -> false
    end
  end

  defp contains?(actual, expected) when is_list(actual),
    do: Enum.any?(actual, &equal?(&1, expected))

  defp contains?(actual, expected) when is_binary(actual) and is_binary(expected),
    do: String.contains?(text(actual), text(expected))

  defp contains?(_actual, _expected), do: false

  defp wildcard_match?(actual, pattern) when is_binary(pattern) do
    case scalar_text(actual) do
      nil -> false
      value -> pattern |> wildcard_regex() |> Regex.match?(value)
    end
  end

  defp wildcard_match?(_actual, _pattern), do: false

  defp wildcard_regex(pattern) do
    body = pattern |> String.split("*") |> Enum.map_join(".*", &Regex.escape/1)
    Regex.compile!("\\A" <> body <> "\\z", "is")
  end

  defp number(n) when is_number(n), do: {:ok, n}

  defp number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp number(_other), do: :error

  defp text(value) do
    case scalar_text(value) do
      nil -> value
      string -> String.downcase(string)
    end
  end

  defp scalar_text(value) when is_binary(value), do: value
  defp scalar_text(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp scalar_text(_value), do: nil
end
