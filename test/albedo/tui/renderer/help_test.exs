defmodule Albedo.TUI.Renderer.HelpTest do
  use ExUnit.Case, async: true

  alias Albedo.TUI.Renderer.Help

  describe "build_help_line/4" do
    test "builds title line for row 1" do
      state = %{}
      result = Help.build_help_line(1, state, 80, 40)

      assert String.contains?(result, "Help")
    end

    test "builds separator line for row 2" do
      state = %{}
      result = Help.build_help_line(2, state, 80, 40)

      assert String.contains?(result, "─")
    end

    test "builds footer line for last row" do
      state = %{}
      result = Help.build_help_line(40, state, 80, 40)

      assert String.contains?(result, "Esc") or String.contains?(result, "close")
    end

    test "builds content lines for middle rows" do
      state = %{}
      result = Help.build_help_line(5, state, 80, 40)

      assert is_binary(result)
    end

    test "returns spaces for out of range content" do
      state = %{}
      result = Help.build_help_line(100, state, 80, 40)

      assert String.trim(result) == "" or String.contains?(result, " ")
    end

    test "includes keyboard shortcuts in content" do
      state = %{}

      lines =
        for row <- 3..30 do
          Help.build_help_line(row, state, 80, 40)
        end

      content = Enum.join(lines, "\n")

      assert String.contains?(content, "Navigation") or String.contains?(content, "j")
    end
  end
end
