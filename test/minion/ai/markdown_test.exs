defmodule Minion.AI.MarkdownTest do
  use ExUnit.Case, async: true

  alias Minion.AI.Markdown

  test "renders headings, emphasis, lists, code spans and links" do
    html =
      rendered("""
      # Title

      Disk on **web-1** is full, see [runbook](https://wiki.example/disk).

      - check `df -h`
      - restart the service

      1. first
      2. second
      """)

    assert html =~ "<h1>Title</h1>"
    assert html =~ "<p>"
    assert html =~ "<strong>web-1</strong>"
    assert html =~ ~s(<a href="https://wiki.example/disk")
    assert html =~ "<li>check <code>df -h</code></li>"
    assert html =~ "<ul>" and html =~ "</ul>"
    assert html =~ "<ol><li>first</li><li>second</li></ol>"
  end

  test "escapes HTML and drops dangerous link schemes" do
    html = rendered("<script>alert(1)</script>\n\n[click](javascript:alert(1))")

    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
    assert html =~ "click"
    refute html =~ "javascript:"
  end

  test "fenced code keeps its line breaks and is escaped" do
    html = rendered("```elixir\nIO.puts(\"<hi>\")\n```")

    assert html =~ "<pre><code>"
    assert html =~ "&lt;hi&gt;"
    refute html =~ "<hi>"
  end

  test "markup inside code spans is left alone" do
    assert rendered("use `**not bold**` here") =~ "<code>**not bold**</code>"
  end

  test "quotes and rules get their own elements" do
    html = rendered("> check the runbook\n\n---")

    assert html =~ "<blockquote>check the runbook</blockquote>"
    assert html =~ "<hr>"
  end

  test "nil renders as empty safe html" do
    assert Markdown.render(nil) == {:safe, ""}
  end

  defp rendered(text) do
    text |> Markdown.render() |> Phoenix.HTML.safe_to_string()
  end
end
