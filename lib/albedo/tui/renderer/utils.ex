defmodule Albedo.TUI.Renderer.Utils do
  @moduledoc """
  Shared utilities for TUI rendering: colors, borders, text wrapping.
  """

  @border_chars %{
    top_left: "┌",
    top_right: "┐",
    bottom_left: "└",
    bottom_right: "┘",
    horizontal: "─",
    vertical: "│"
  }

  @border_chars_heavy %{
    top_left: "┏",
    top_right: "┓",
    bottom_left: "┗",
    bottom_right: "┛",
    horizontal: "━",
    vertical: "┃"
  }

  @colors %{
    reset: "\e[0m",
    bold: "\e[1m",
    dim: "\e[2m",
    black: "\e[30m",
    red: "\e[31m",
    green: "\e[32m",
    yellow: "\e[33m",
    magenta: "\e[35m",
    white: "\e[37m",
    bg_blue: "\e[44m",
    bg_cyan: "\e[46m",
    kanagawa_orange: "\e[38;2;255;160;102m",
    bg_kanagawa_sky_blue: "\e[48;2;127;180;202m"
  }

  def colors, do: @colors
  def border_chars, do: @border_chars
  def border_chars_heavy, do: @border_chars_heavy
  def border_chars(true), do: @border_chars_heavy
  def border_chars(false), do: @border_chars

  def build_top_border(title, width, border_color, is_active) do
    colors = @colors
    chars = if is_active, do: @border_chars_heavy, else: @border_chars
    title_color = if is_active, do: colors.bold <> colors.green, else: colors.white
    bar_width = width - 2
    title_len = String.length(title)
    left_bar = div(bar_width - title_len, 2)
    right_bar = bar_width - title_len - left_bar

    border_color <>
      chars.top_left <>
      String.duplicate(chars.horizontal, left_bar) <>
      title_color <>
      title <>
      border_color <>
      String.duplicate(chars.horizontal, right_bar) <>
      chars.top_right <> colors.reset
  end

  def build_bottom_border(width, border_color, is_active \\ false) do
    chars = if is_active, do: @border_chars_heavy, else: @border_chars

    border_color <>
      chars.bottom_left <>
      String.duplicate(chars.horizontal, width - 2) <>
      chars.bottom_right <> @colors.reset
  end

  def wrap_text(text, width) when is_binary(text) and width > 0 do
    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line(&1, width))
  end

  def wrap_text(_, _), do: []

  def wrap_line("", _width), do: [""]

  def wrap_line(line, width) do
    words = String.split(line, ~r/\s+/, trim: false)
    wrap_words(words, width, [], "")
  end

  defp wrap_words([], _width, lines, current) do
    Enum.reverse([current | lines])
  end

  defp wrap_words([word | rest], width, lines, "") do
    wrap_words(rest, width, lines, word)
  end

  defp wrap_words([word | rest], width, lines, current) do
    candidate = current <> " " <> word

    if String.length(candidate) <= width do
      wrap_words(rest, width, lines, candidate)
    else
      wrap_words(rest, width, [current | lines], word)
    end
  end

  def pad_content(text, width) do
    String.pad_trailing(String.slice(text, 0, width), width)
  end

  def status_indicator(:pending), do: "○"
  def status_indicator(:in_progress), do: "●"
  def status_indicator(:completed), do: "✓"

  def status_color(:pending), do: @colors.dim
  def status_color(:in_progress), do: @colors.yellow
  def status_color(:completed), do: @colors.green

  def priority_color(:urgent), do: @colors.red
  def priority_color(:high), do: @colors.yellow
  def priority_color(:medium), do: ""
  def priority_color(:low), do: @colors.dim
  def priority_color(:none), do: @colors.dim

  def project_state_indicator("completed"), do: "✓"
  def project_state_indicator("failed"), do: "✗"
  def project_state_indicator("paused"), do: "⏸"
  def project_state_indicator(_), do: "○"

  def field_label(:title), do: "Title:"
  def field_label(:description), do: "Description:"
  def field_label(:type), do: "Type (feature/enhancement/bugfix/chore/docs/test):"
  def field_label(:priority), do: "Priority (urgent/high/medium/low/none):"
  def field_label(:estimate), do: "Points (1-13):"
  def field_label(:labels), do: "Labels (comma-separated):"
  def field_label(_), do: "Field:"

  def get_display_value(ticket, :title), do: ticket.title || ""
  def get_display_value(ticket, :description), do: ticket.description || ""
  def get_display_value(ticket, :type), do: to_string(ticket.type)
  def get_display_value(ticket, :priority), do: to_string(ticket.priority)

  def get_display_value(ticket, :estimate),
    do: if(ticket.estimate, do: to_string(ticket.estimate), else: "")

  def get_display_value(ticket, :labels), do: Enum.join(ticket.labels, ", ")
  def get_display_value(_, _), do: ""

  def color_escape_length(str) do
    escape_pattern = ~r/\e\[[0-9;]*m/
    escapes = Regex.scan(escape_pattern, str)
    Enum.reduce(escapes, 0, fn [match], acc -> acc + String.length(match) end)
  end
end
