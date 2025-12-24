defmodule Albedo.Output.MarkdownTest do
  use ExUnit.Case, async: true

  alias Albedo.Output.Markdown

  describe "heading/2" do
    test "creates h1 heading by default" do
      result = Markdown.heading("Title")
      assert result == "# Title\n"
    end

    test "creates heading at specified level" do
      assert Markdown.heading("Title", 1) == "# Title\n"
      assert Markdown.heading("Title", 2) == "## Title\n"
      assert Markdown.heading("Title", 3) == "### Title\n"
    end
  end

  describe "table/2" do
    test "creates a markdown table" do
      headers = ["Name", "Age"]
      rows = [["Alice", "30"], ["Bob", "25"]]

      result = Markdown.table(headers, rows)

      assert String.contains?(result, "| Name | Age |")
      assert String.contains?(result, "| --- | --- |")
      assert String.contains?(result, "| Alice | 30 |")
      assert String.contains?(result, "| Bob | 25 |")
    end

    test "escapes pipe characters in cells" do
      headers = ["Value"]
      rows = [["a|b"]]

      result = Markdown.table(headers, rows)

      assert String.contains?(result, "a\\|b")
    end
  end

  describe "code_block/2" do
    test "creates code block without language" do
      result = Markdown.code_block("code here")

      assert String.contains?(result, "```")
      assert String.contains?(result, "code here")
    end

    test "creates code block with language" do
      result = Markdown.code_block("def foo; end", "elixir")

      assert String.contains?(result, "```elixir")
      assert String.contains?(result, "def foo; end")
    end
  end

  describe "code/1" do
    test "creates inline code" do
      result = Markdown.code("variable")
      assert result == "`variable`"
    end
  end

  describe "bullet_list/1" do
    test "creates bullet list" do
      result = Markdown.bullet_list(["Item 1", "Item 2", "Item 3"])

      assert result == "- Item 1\n- Item 2\n- Item 3"
    end
  end

  describe "numbered_list/1" do
    test "creates numbered list" do
      result = Markdown.numbered_list(["First", "Second", "Third"])

      assert result == "1. First\n2. Second\n3. Third"
    end
  end

  describe "checkbox_list/2" do
    test "creates checkbox list" do
      result = Markdown.checkbox_list(["Task 1", "Task 2"])

      assert result == "- [ ] Task 1\n- [ ] Task 2"
    end

    test "marks specified items as checked" do
      result = Markdown.checkbox_list(["Task 1", "Task 2"], ["Task 1"])

      assert String.contains?(result, "- [x] Task 1")
      assert String.contains?(result, "- [ ] Task 2")
    end
  end

  describe "blockquote/1" do
    test "creates blockquote" do
      result = Markdown.blockquote("Quote text")
      assert result == "> Quote text"
    end

    test "handles multiline quotes" do
      result = Markdown.blockquote("Line 1\nLine 2")
      assert result == "> Line 1\n> Line 2"
    end
  end

  describe "horizontal_rule/0" do
    test "creates horizontal rule" do
      result = Markdown.horizontal_rule()
      assert result == "\n---\n"
    end
  end

  describe "link/2" do
    test "creates markdown link" do
      result = Markdown.link("Click here", "https://example.com")
      assert result == "[Click here](https://example.com)"
    end
  end

  describe "bold/1" do
    test "creates bold text" do
      result = Markdown.bold("important")
      assert result == "**important**"
    end
  end

  describe "italic/1" do
    test "creates italic text" do
      result = Markdown.italic("emphasis")
      assert result == "*emphasis*"
    end
  end

  describe "mermaid/1" do
    test "creates mermaid diagram block" do
      result = Markdown.mermaid("graph TD\n  A --> B")

      assert String.contains?(result, "```mermaid")
      assert String.contains?(result, "graph TD")
    end
  end

  describe "collapsible/2" do
    test "creates collapsible section" do
      result = Markdown.collapsible("Details", "Hidden content")

      assert String.contains?(result, "<details>")
      assert String.contains?(result, "<summary>Details</summary>")
      assert String.contains?(result, "Hidden content")
      assert String.contains?(result, "</details>")
    end
  end

  describe "escape_cell/1" do
    test "escapes pipe characters" do
      assert Markdown.escape_cell("a|b") == "a\\|b"
    end

    test "replaces newlines with spaces" do
      assert Markdown.escape_cell("line1\nline2") == "line1 line2"
    end

    test "converts non-strings to strings" do
      assert Markdown.escape_cell(123) == "123"
      assert Markdown.escape_cell(:atom) == "atom"
    end
  end

  describe "join_sections/1" do
    test "joins sections with double newlines" do
      result = Markdown.join_sections(["Section 1", "Section 2"])
      assert result == "Section 1\n\nSection 2"
    end

    test "filters out empty and nil sections" do
      result = Markdown.join_sections(["Section 1", "", nil, "Section 2"])
      assert result == "Section 1\n\nSection 2"
    end
  end
end
