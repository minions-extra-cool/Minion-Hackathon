defmodule Minion.AI.Markdown do
  @spec render(String.t() | nil) :: Phoenix.HTML.safe()
  def render(nil), do: Phoenix.HTML.raw("")

  def render(text) when is_binary(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> parse_blocks([])
    |> Enum.map_join("\n", &to_html/1)
    |> Phoenix.HTML.raw()
  end

  defp parse_blocks([], acc), do: Enum.reverse(acc)
  defp parse_blocks(["" | rest], acc), do: parse_blocks(rest, acc)

  defp parse_blocks(["```" <> _info = fence | rest], acc) do
    {code, rest} = take_code(rest, [])
    parse_blocks(rest, [{:code, fence, code} | acc])
  end

  defp parse_blocks([<<"#", _::binary>> = line | rest], acc) do
    {level, text} = heading(line)
    parse_blocks(rest, [{:heading, level, text} | acc])
  end

  defp parse_blocks([<<mark, " ", _::binary>> | _] = lines, acc)
       when mark in [?-, ?*, ?+] do
    marker = <<mark, " ">>
    {items, rest} = take_marked(lines, marker)
    parse_blocks(rest, [{:ul, items} | acc])
  end

  defp parse_blocks([<<digit, ". ", _::binary>> | _] = lines, acc)
       when digit in ?0..?9 do
    {items, rest} =
      Enum.split_while(lines, fn
        <<d, ". ", _::binary>> -> d in ?0..?9
        _ -> false
      end)

    items = Enum.map(items, fn <<_, ". ", text::binary>> -> text end)
    parse_blocks(rest, [{:ol, items} | acc])
  end

  defp parse_blocks([<<"> ", _::binary>> | _] = lines, acc) do
    {quoted, rest} = Enum.split_while(lines, &String.starts_with?(&1, "> "))
    text = Enum.map_join(quoted, " ", &String.slice(&1, 2..-1//1))
    parse_blocks(rest, [{:quote, text} | acc])
  end

  defp parse_blocks([line | rest], acc) when line in ["---", "***", "___"],
    do: parse_blocks(rest, [:hr | acc])

  defp parse_blocks(lines, acc) do
    {paragraph, rest} = Enum.split_while(lines, &paragraph_line?(&1))
    parse_blocks(rest, [{:paragraph, paragraph} | acc])
  end

  defp take_code(["```" <> _closing | rest], acc),
    do: {acc |> Enum.reverse() |> Enum.join("\n"), rest}

  defp take_code([], acc), do: {acc |> Enum.reverse() |> Enum.join("\n"), []}

  defp take_code([line | rest], acc), do: take_code(rest, [line | acc])

  defp take_marked(lines, marker) do
    {marked, rest} = Enum.split_while(lines, &String.starts_with?(&1, marker))

    items = Enum.map(marked, &String.slice(&1, String.length(marker)..-1//1))
    {items, rest}
  end

  defp heading(line) do
    level =
      line
      |> String.graphemes()
      |> Enum.take_while(&(&1 == "#"))
      |> length()
      |> min(6)

    {level, line |> String.slice(level..-1//1) |> String.trim()}
  end

  defp paragraph_line?(""), do: false
  defp paragraph_line?(line), do: not block_start?(line)

  defp block_start?(line) do
    String.starts_with?(line, "```") or
      String.starts_with?(line, "#") or
      String.starts_with?(line, "> ") or
      line in ["---", "***", "___"] or
      bullet_start?(line) or
      ordered_start?(line)
  end

  defp bullet_start?(<<mark, " ", _::binary>>), do: mark in [?-, ?*, ?+]
  defp bullet_start?(_line), do: false

  defp ordered_start?(<<digit, ". ", _::binary>>), do: digit in ?0..?9
  defp ordered_start?(_line), do: false

  defp to_html({:heading, level, text}), do: "<h#{level}>#{inline(text)}</h#{level}>"
  defp to_html({:paragraph, text}), do: "<p>#{inline(text)}</p>"

  defp to_html({:ul, items}),
    do: "<ul>" <> Enum.map_join(items, &"<li>#{inline(&1)}</li>") <> "</ul>"

  defp to_html({:ol, items}),
    do: "<ol>" <> Enum.map_join(items, &"<li>#{inline(&1)}</li>") <> "</ol>"

  defp to_html({:code, _fence, code}),
    do: "<pre><code>" <> escaped(code) <> "</code></pre>"

  defp to_html({:quote, text}), do: "<blockquote>#{inline(text)}</blockquote>"
  defp to_html(:hr), do: "<hr>"

  defp escaped(text) do
    text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  defp inline(text) do
    escaped = escaped(text)

    escaped
    |> String.split("`")
    |> Enum.with_index()
    |> Enum.map_join("", fn
      {part, index} ->
        if rem(index, 2) == 0,
          do: part |> linkify() |> boldify() |> italicize(),
          else: "<code>" <> part <> "</code>"
    end)
  end

  defp linkify(text) do
    Regex.replace(~r/\[([^\]]+)\]\(([^)\s]+)\)/, text, fn _whole, label, destination ->
      if safe_url?(destination),
        do: ~s(<a href="#{destination}" target="_blank" rel="noreferrer">#{label}</a>),
        else: label
    end)
  end

  defp boldify(text) do
    text
    |> then(
      &Regex.replace(~r/\*\*([^*]+)\*\*/, &1, fn _, inner -> "<strong>#{inner}</strong>" end)
    )
    |> then(&Regex.replace(~r/__([^_]+)__/, &1, fn _, inner -> "<strong>#{inner}</strong>" end))
  end

  defp italicize(text) do
    Regex.replace(~r/(?<!\*)\*([^*\n]+)\*(?!\*)/, text, fn _, inner -> "<em>#{inner}</em>" end)
  end

  defp safe_url?(destination) do
    destination = destination |> String.trim() |> String.downcase()

    cond do
      destination == "" -> false
      String.starts_with?(destination, "#") -> true
      String.starts_with?(destination, "/") -> true
      String.starts_with?(destination, "http://") -> true
      String.starts_with?(destination, "https://") -> true
      String.starts_with?(destination, "mailto:") -> true
      not String.contains?(destination, ":") -> true
      true -> false
    end
  end
end
