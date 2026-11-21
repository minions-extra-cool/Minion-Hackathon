defmodule MinionWeb.Markdown do
  @fence ~r/^\s*```/
  @heading ~r/^(\#{1,6})\s+(.*)$/
  @thematic_break ["---", "***", "___"]
  @quote ~r/^\s*>\s?(.*)$/
  @ordered_item ~r/^\s*(\d+)[.)]\s+(.*)$/
  @unordered_item ~r/^\s*[-*+]\s+(.*)$/
  @code_span ~r/`([^`]+)`/
  @link ~r/\[([^\]]+)\]\(([^)\s]+)\)/
  @bold ~r/\*\*(.+?)\*\*/
  @italic ~r/__(.+?)__|(?<!\*)\*([^*\s][^*]*?)\*(?!\*)/
  @standalone_blocks [:code, :heading, :rule]

  @spec to_html(String.t() | nil) :: Phoenix.HTML.safe()
  def to_html(nil), do: Phoenix.HTML.raw("")

  def to_html(text) do
    text
    |> String.split(~r/\r?\n/)
    |> classify_lines([])
    |> Enum.with_index()
    |> Enum.chunk_by(&chunk_key/1)
    |> Enum.map(fn chunk -> chunk |> Enum.map(&elem(&1, 0)) |> block() end)
    |> Phoenix.HTML.raw()
  end

  defp classify_lines([], classified), do: Enum.reverse(classified)

  defp classify_lines([line | rest], classified) do
    if Regex.match?(@fence, line) do
      {code, after_code} = Enum.split_while(rest, &(not Regex.match?(@fence, &1)))
      classify_lines(Enum.drop(after_code, 1), [{:code, nil, Enum.join(code, "\n")} | classified])
    else
      classify_lines(rest, [classify(line) | classified])
    end
  end

  defp classify(line) do
    cond do
      match = Regex.run(@heading, line) ->
        [_line, hashes, content] = match
        {:heading, String.length(hashes), content}

      String.trim(line) in @thematic_break ->
        {:rule, nil, nil}

      match = Regex.run(@quote, line) ->
        [_line, content] = match
        {:quote, nil, content}

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

  defp chunk_key({{type, _, _}, index}) when type in @standalone_blocks, do: {type, index}
  defp chunk_key({{type, _, _}, _index}), do: type

  defp block([{:blank, _, _} | _]), do: []

  defp block([{:code, _, code}]), do: ["<pre><code>", escape(code), "</code></pre>"]

  defp block([{:heading, level, content}]),
    do: ["<h#{level}>", inline(content), "</h#{level}>"]

  defp block([{:rule, _, _}]), do: "<hr>"

  defp block([{:quote, _, _} | _] = lines),
    do: ["<blockquote>", lines_with_breaks(lines), "</blockquote>"]

  defp block([{:text, _, _} | _] = lines), do: ["<p>", lines_with_breaks(lines), "</p>"]

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

  defp lines_with_breaks(lines),
    do: lines |> Enum.map(&inline(elem(&1, 2))) |> Enum.intersperse("<br>")

  defp start_attribute(1), do: []
  defp start_attribute(start), do: ~s( start="#{start}")

  defp list_items(items), do: Enum.map(items, &["<li>", inline(elem(&1, 2)), "</li>"])

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp inline(text) do
    @code_span
    |> Regex.split(escape(text), include_captures: true)
    |> Enum.map(&format_span/1)
  end

  defp format_span("`" <> _ = span) do
    code = String.slice(span, 1..-2//1)
    [~s(<code class="bg-base-300 px-1 font-mono text-[0.9em]">), code, "</code>"]
  end

  defp format_span(span) do
    span
    |> link()
    |> String.replace(@bold, "<strong>\\1</strong>")
    |> String.replace(@italic, "<em>\\1\\2</em>")
  end

  defp link(span) do
    Regex.replace(@link, span, fn _whole, label, destination ->
      if safe_destination?(destination),
        do: ~s(<a href="#{destination}" target="_blank" rel="noreferrer">#{label}</a>),
        else: label
    end)
  end

  defp safe_destination?(destination) do
    destination = String.downcase(destination)

    String.starts_with?(destination, ["http://", "https://", "mailto:", "/", "#"]) or
      not String.contains?(destination, ":")
  end
end
