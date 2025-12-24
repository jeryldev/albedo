defmodule Albedo.Agents.BaseTest do
  use ExUnit.Case, async: true

  alias Albedo.Agents.Base

  describe "markdown_section/2" do
    test "creates markdown section with title and content" do
      result = Base.markdown_section("Test Title", "Test content here")
      assert result =~ "## Test Title"
      assert result =~ "Test content here"
    end

    test "handles empty content" do
      result = Base.markdown_section("Empty Section", "")
      assert result =~ "## Empty Section"
    end

    test "handles multiline content" do
      content = "Line 1\nLine 2\nLine 3"
      result = Base.markdown_section("Multi", content)
      assert result =~ "Line 1"
      assert result =~ "Line 3"
    end
  end

  describe "markdown_table/2" do
    test "creates table with headers and rows" do
      headers = ["Name", "Value"]
      rows = [["foo", "1"], ["bar", "2"]]
      result = Base.markdown_table(headers, rows)

      assert result =~ "| Name | Value |"
      assert result =~ "| --- | --- |"
      assert result =~ "| foo | 1 |"
      assert result =~ "| bar | 2 |"
    end

    test "handles single column table" do
      headers = ["Item"]
      rows = [["First"], ["Second"]]
      result = Base.markdown_table(headers, rows)

      assert result =~ "| Item |"
      assert result =~ "| First |"
    end

    test "handles empty rows" do
      headers = ["Col1", "Col2"]
      rows = []
      result = Base.markdown_table(headers, rows)

      assert result =~ "| Col1 | Col2 |"
      assert result =~ "| --- | --- |"
    end
  end

  describe "code_block/2" do
    test "creates code block with default language" do
      result = Base.code_block("def hello, do: :world")
      assert result =~ "```elixir"
      assert result =~ "def hello, do: :world"
      assert result =~ "```"
    end

    test "creates code block with custom language" do
      result = Base.code_block("console.log('hello')", "javascript")
      assert result =~ "```javascript"
      assert result =~ "console.log('hello')"
    end

    test "handles multiline code" do
      code = """
      defmodule Test do
        def hello do
          :world
        end
      end
      """

      result = Base.code_block(code)
      assert result =~ "defmodule Test do"
      assert result =~ ":world"
    end
  end

  describe "mermaid_diagram/1" do
    test "creates mermaid diagram block" do
      diagram = "graph TD\n  A --> B"
      result = Base.mermaid_diagram(diagram)

      assert result =~ "```mermaid"
      assert result =~ "graph TD"
      assert result =~ "A --> B"
      assert result =~ "```"
    end
  end
end
