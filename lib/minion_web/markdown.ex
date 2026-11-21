defmodule MinionWeb.Markdown do
  @ordered_item ~r/^\s*(\d+)[.)]\s+(.*)$/
  @unordered_item ~r/^\s*[-*+]\s+(.*)$/
  @code_span ~r/`([^`]+)`/
  @bold ~r/\*\*(.+?)\*\*/
  @italic ~r/__(.+?)__/

  @spec to_html(String.t() | nil) :: Phoenix.HTML.safe()
  def to_html(nil), do: Phoenix.HTML.raw("")

  def to_html(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map(&classify/1)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(&block/1)
    |> Phoenix.HTML.raw()
  end

  defp classify(line) do
    cond do
      match = Regex.run(@ordered_item, line) ->
        [_line, number, content] = match
        {:ordered, String.to_integer(number), content}

      match = Regex.run(@unordered_item, line) ->
        [_line, content] = match
        {:unordered, nil, content}

      String.trim(line) == "" ->
        {:blank, nil, nil}

      true ->
        {:text, nil, line}
    end
  end

  defp block([{:blank, _, _} | _]), do: []

  defp block([{:text, _, _} | _] = lines),
    do: ["<p>", lines |> Enum.map(&inline(elem(&1, 2))) |> Enum.intersperse("<br>"), "</p>"]

  defp block([{:unordered, _, _} | _] = items),
    do: [~s(<ul class="list-disc space-y-1 pl-6">), list_items(items), "</ul>"]

  defp block([{:ordered, start, _} | _] = items),
    do: [
      ~s(<ol class="list-decimal space-y-1 pl-6"),
      start_attribute(start),
      ">",
      list_items(items),
      "</ol>"
    ]

  defp start_attribute(1), do: []
  defp start_attribute(start), do: ~s( start="#{start}")

  defp list_items(items), do: Enum.map(items, &["<li>", inline(elem(&1, 2)), "</li>"])

  defp inline(text) do
    escaped = text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    @code_span
    |> Regex.split(escaped, include_captures: true)
    |> Enum.map(&format_span/1)
  end

  defp format_span("`" <> _ = span) do
    code = String.slice(span, 1..-2//1)
    [~s(<code class="bg-base-300 px-1 font-mono text-[0.9em]">), code, "</code>"]
  end

  defp format_span(span) do
    span
    |> String.replace(@bold, "<strong>\\1</strong>")
    |> String.replace(@italic, "<em>\\1</em>")
  end
end
