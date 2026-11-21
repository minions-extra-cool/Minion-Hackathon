defmodule MinionWeb.MarkdownTest do
  use ExUnit.Case, async: true

  alias MinionWeb.Markdown

  defp html(text), do: text |> Markdown.to_html() |> Phoenix.HTML.safe_to_string()

  test "consecutive numbered lines become an ordered list" do
    assert html("1. Check disk\n2. Clear logs") ==
             ~s(<ol class="list-decimal space-y-1 pl-6"><li>Check disk</li><li>Clear logs</li></ol>)
  end

  test "an ordered list keeps its starting number" do
    assert html("3) Page on-call") =~ ~s(<ol class="list-decimal space-y-1 pl-6" start="3">)
  end

  test "dash, star and plus lines become an unordered list" do
    assert html("- one\n* two\n+ three") ==
             ~s(<ul class="list-disc space-y-1 pl-6"><li>one</li><li>two</li><li>three</li></ul>)
  end

  test "text lines form paragraphs split by blank lines, keeping line breaks" do
    assert html("first\nsecond\n\nthird") == "<p>first<br>second</p><p>third</p>"
  end

  test "a list right after text starts a new block" do
    assert html("Steps:\n- look") ==
             ~s(<p>Steps:</p><ul class="list-disc space-y-1 pl-6"><li>look</li></ul>)
  end

  test "bold, italic and monospace" do
    assert html("**now** __maybe__ `df -h`") ==
             "<p><strong>now</strong> <em>maybe</em> " <>
               ~s(<code class="bg-base-300 px-1 font-mono text-[0.9em]">df -h</code></p>)
  end

  test "markers inside code are left as typed" do
    assert html("`**not bold**`") =~ ">**not bold**</code>"
  end

  test "a line starting with bold is not a list item" do
    assert html("**Note** this") == "<p><strong>Note</strong> this</p>"
  end

  test "HTML in the text is escaped" do
    assert html("<script>alert(1)</script> **<b>x</b>**") ==
             "<p>&lt;script&gt;alert(1)&lt;/script&gt; <strong>&lt;b&gt;x&lt;/b&gt;</strong></p>"
  end

  test "unclosed markers stay as text" do
    assert html("**half and `tick") == "<p>**half and `tick</p>"
  end
end
