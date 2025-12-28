defmodule Albedo.TUI.Renderer.UtilsTest do
  use ExUnit.Case, async: true

  alias Albedo.TUI.Renderer.Utils

  describe "wrap_text/2" do
    test "wraps long text at specified width" do
      text = "This is a long line that should be wrapped"
      result = Utils.wrap_text(text, 20)

      assert is_list(result)
      assert Enum.all?(result, &(String.length(&1) <= 20))
    end

    test "preserves newlines in input" do
      text = "Line one\nLine two"
      result = Utils.wrap_text(text, 50)

      assert length(result) >= 2
    end

    test "handles empty string" do
      assert Utils.wrap_text("", 20) == [""]
    end

    test "returns empty list for nil or invalid width" do
      assert Utils.wrap_text(nil, 20) == []
      assert Utils.wrap_text("text", 0) == []
      assert Utils.wrap_text("text", -1) == []
    end

    test "handles text shorter than width" do
      text = "Short"
      result = Utils.wrap_text(text, 20)

      assert result == ["Short"]
    end
  end

  describe "wrap_line/2" do
    test "wraps single line at word boundaries" do
      line = "Hello world this is a test"
      result = Utils.wrap_line(line, 12)

      assert is_list(result)
      assert length(result) > 1
    end

    test "handles empty string" do
      assert Utils.wrap_line("", 20) == [""]
    end

    test "handles single word longer than width" do
      result = Utils.wrap_line("superlongword", 5)

      assert is_list(result)
    end
  end

  describe "pad_content/2" do
    test "pads short text to width" do
      result = Utils.pad_content("Hi", 10)

      assert String.length(result) == 10
      assert String.starts_with?(result, "Hi")
    end

    test "truncates long text to width" do
      result = Utils.pad_content("This is way too long", 10)

      assert String.length(result) == 10
    end

    test "handles exact width" do
      result = Utils.pad_content("ExactLen10", 10)

      assert result == "ExactLen10"
    end
  end

  describe "status_indicator/1" do
    test "returns correct indicator for pending" do
      assert Utils.status_indicator(:pending) == "○"
    end

    test "returns correct indicator for in_progress" do
      assert Utils.status_indicator(:in_progress) == "●"
    end

    test "returns correct indicator for completed" do
      assert Utils.status_indicator(:completed) == "✓"
    end
  end

  describe "status_color/1" do
    test "returns dim for pending" do
      result = Utils.status_color(:pending)
      assert is_binary(result)
      assert String.contains?(result, "\e[")
    end

    test "returns yellow for in_progress" do
      result = Utils.status_color(:in_progress)
      assert String.contains?(result, "33")
    end

    test "returns green for completed" do
      result = Utils.status_color(:completed)
      assert String.contains?(result, "32")
    end
  end

  describe "priority_color/1" do
    test "returns red for urgent" do
      result = Utils.priority_color(:urgent)
      assert String.contains?(result, "31")
    end

    test "returns yellow for high" do
      result = Utils.priority_color(:high)
      assert String.contains?(result, "33")
    end

    test "returns empty string for medium" do
      assert Utils.priority_color(:medium) == ""
    end

    test "returns dim for low and none" do
      assert Utils.priority_color(:low) == Utils.priority_color(:none)
    end
  end

  describe "project_state_indicator/1" do
    test "returns checkmark for completed" do
      assert Utils.project_state_indicator("completed") == "✓"
    end

    test "returns X for failed" do
      assert Utils.project_state_indicator("failed") == "✗"
    end

    test "returns pause for paused" do
      assert Utils.project_state_indicator("paused") == "⏸"
    end

    test "returns circle for other states" do
      assert Utils.project_state_indicator("running") == "○"
      assert Utils.project_state_indicator("unknown") == "○"
    end
  end

  describe "field_label/1" do
    test "returns label for known fields" do
      assert Utils.field_label(:title) == "Title:"
      assert Utils.field_label(:description) == "Description:"
      assert Utils.field_label(:type) =~ "Type"
      assert Utils.field_label(:priority) =~ "Priority"
      assert Utils.field_label(:estimate) =~ "Points"
      assert Utils.field_label(:labels) =~ "Labels"
    end

    test "returns default label for unknown fields" do
      assert Utils.field_label(:unknown) == "Field:"
    end
  end

  describe "get_display_value/2" do
    test "returns title from ticket" do
      ticket = %{
        title: "My Title",
        description: nil,
        type: :feature,
        priority: :medium,
        estimate: nil,
        labels: []
      }

      assert Utils.get_display_value(ticket, :title) == "My Title"
    end

    test "returns empty string for nil values" do
      ticket = %{
        title: nil,
        description: nil,
        type: :feature,
        priority: :medium,
        estimate: nil,
        labels: []
      }

      assert Utils.get_display_value(ticket, :title) == ""
      assert Utils.get_display_value(ticket, :description) == ""
    end

    test "converts type and priority to string" do
      ticket = %{
        title: "T",
        description: nil,
        type: :bugfix,
        priority: :high,
        estimate: nil,
        labels: []
      }

      assert Utils.get_display_value(ticket, :type) == "bugfix"
      assert Utils.get_display_value(ticket, :priority) == "high"
    end

    test "formats estimate as string" do
      ticket = %{
        title: "T",
        description: nil,
        type: :feature,
        priority: :medium,
        estimate: 5,
        labels: []
      }

      assert Utils.get_display_value(ticket, :estimate) == "5"
    end

    test "joins labels with comma" do
      ticket = %{
        title: "T",
        description: nil,
        type: :feature,
        priority: :medium,
        estimate: nil,
        labels: ["a", "b", "c"]
      }

      assert Utils.get_display_value(ticket, :labels) == "a, b, c"
    end

    test "returns empty string for unknown field" do
      ticket = %{title: "T"}
      assert Utils.get_display_value(ticket, :unknown) == ""
    end
  end

  describe "color_escape_length/1" do
    test "returns 0 for string without escapes" do
      assert Utils.color_escape_length("plain text") == 0
    end

    test "counts escape sequence length" do
      colored = "\e[32mgreen\e[0m"
      length = Utils.color_escape_length(colored)
      assert length > 0
    end

    test "handles multiple escape sequences" do
      multi = "\e[1m\e[32mbold green\e[0m"
      length = Utils.color_escape_length(multi)
      assert length > Utils.color_escape_length("\e[32mgreen\e[0m")
    end
  end

  describe "build_top_border/4" do
    test "builds border with title" do
      result = Utils.build_top_border("Test", 20, "", false)

      assert String.contains?(result, "Test")
      assert String.contains?(result, "─")
    end

    test "uses heavy chars when active" do
      active = Utils.build_top_border("Test", 20, "", true)
      inactive = Utils.build_top_border("Test", 20, "", false)

      assert String.contains?(active, "━")
      assert String.contains?(inactive, "─")
    end
  end

  describe "build_bottom_border/3" do
    test "builds bottom border" do
      result = Utils.build_bottom_border(20, "", false)

      assert String.contains?(result, "└")
      assert String.contains?(result, "┘")
    end

    test "uses heavy chars when active" do
      active = Utils.build_bottom_border(20, "", true)

      assert String.contains?(active, "┗")
      assert String.contains?(active, "┛")
    end
  end

  describe "colors/0 and border_chars/0" do
    test "returns color map" do
      colors = Utils.colors()

      assert is_map(colors)
      assert Map.has_key?(colors, :reset)
      assert Map.has_key?(colors, :green)
      assert Map.has_key?(colors, :red)
    end

    test "returns border chars map" do
      chars = Utils.border_chars()

      assert is_map(chars)
      assert Map.has_key?(chars, :top_left)
      assert Map.has_key?(chars, :horizontal)
      assert Map.has_key?(chars, :vertical)
    end

    test "returns heavy or light chars based on flag" do
      light = Utils.border_chars(false)
      heavy = Utils.border_chars(true)

      assert light.horizontal == "─"
      assert heavy.horizontal == "━"
    end
  end
end
