defmodule Albedo.TUI.Renderer do
  @moduledoc """
  Renders the TUI interface using ANSI escape codes.
  Implements a lazygit-inspired 3-panel layout.

  Delegates rendering to focused sub-modules:
  - Renderer.Utils - Shared utilities (colors, borders, text wrapping)
  - Renderer.Help - Help screen overlay
  - Renderer.Modal - Modal dialogs for plan/analyze
  - Renderer.Panels - Left panel sections (projects, tickets, research)
  - Renderer.Detail - Right panel (detail view, edit mode, file content)
  """

  alias Albedo.TUI.Renderer.{Detail, Help, Modal, Panels, Utils}
  alias Albedo.TUI.{State, Terminal}

  def render(%State{} = state) do
    {width, height} = Terminal.get_size()
    state = %{state | terminal_size: {width, height}}

    output = build_frame(state, width, height)

    IO.write([
      "\e[?25l",
      "\e[H",
      output,
      "\e[?25h"
    ])
  end

  defp build_frame(%{mode: :help} = state, width, height) do
    lines = for row <- 1..height, do: Help.build_help_line(row, state, width, height)
    Enum.intersperse(lines, "\r\n")
  end

  defp build_frame(%{mode: :modal} = state, width, height) do
    base_lines = for row <- 1..height, do: build_line(row, state, width, height)
    modal_lines = Modal.build_modal_overlay(state, width, height)

    merged =
      Enum.zip(base_lines, modal_lines)
      |> Enum.map(fn {base, modal} ->
        if modal == nil, do: base, else: modal
      end)

    Enum.intersperse(merged, "\r\n")
  end

  defp build_frame(state, width, height) do
    lines = for row <- 1..height, do: build_line(row, state, width, height)
    Enum.intersperse(lines, "\r\n")
  end

  defp build_line(row, state, width, height) do
    cond do
      row == height - 1 ->
        build_status_line(state, width)

      row == height ->
        build_message_line(state, width)

      true ->
        build_panel_line(row, state, width, height)
    end
  end

  defp build_status_line(state, width) do
    colors = Utils.colors()
    help_text = mode_help_text(state)
    :erlang.iolist_to_binary([colors.dim, String.pad_trailing(help_text, width), colors.reset])
  end

  defp mode_help_text(%{mode: :edit}),
    do: " Tab:next field  Shift+Tab:prev  Enter:save  Esc:cancel "

  defp mode_help_text(%{mode: :input}), do: " Enter:submit  Esc:cancel "
  defp mode_help_text(%{mode: :confirm}), do: " y:confirm  n:cancel  Esc:cancel "
  defp mode_help_text(%{active_panel: panel}), do: status_bar_help(panel)

  defp build_message_line(%{mode: :input} = state, width) do
    colors = Utils.colors()
    prompt = state.input_prompt || ""
    buffer = state.input_buffer || ""
    cursor = state.input_cursor

    {before, after_cursor} = String.split_at(buffer, cursor)
    cursor_char = if after_cursor == "", do: " ", else: String.first(after_cursor)
    rest = if after_cursor == "", do: "", else: String.slice(after_cursor, 1..-1//1)

    escape_len =
      String.length(colors.bg_cyan) + String.length(colors.reset) + String.length(colors.yellow)

    input_display =
      :erlang.iolist_to_binary([
        prompt,
        before,
        colors.bg_cyan,
        cursor_char,
        colors.reset,
        colors.yellow,
        rest
      ])

    :erlang.iolist_to_binary([
      colors.yellow,
      String.pad_trailing(input_display, width + escape_len),
      colors.reset
    ])
  end

  defp build_message_line(%{mode: :confirm} = state, width) do
    colors = Utils.colors()
    msg = state.confirm_message || ""

    :erlang.iolist_to_binary([
      colors.red,
      colors.bold,
      String.pad_trailing(msg, width),
      colors.reset
    ])
  end

  defp build_message_line(state, width) do
    colors = Utils.colors()
    msg = state.message || ""
    :erlang.iolist_to_binary([colors.yellow, String.pad_trailing(msg, width), colors.reset])
  end

  defp build_panel_line(row, state, width, height) do
    left_width = max(30, div(width, 3))
    right_width = width - left_width

    panel_start = 1
    panel_height = height - 2
    section_height = div(panel_height, 3)

    panel_row = row - panel_start + 1

    left_content =
      Panels.build_left_panel_char(panel_row, state, left_width, section_height, panel_height)

    right_content = Detail.build_right_panel_char(panel_row, state, right_width, panel_height)

    left_content <> right_content
  end

  defp status_bar_help(:projects) do
    " j/k:nav  Tab:panel  Enter:load  n:new  p:plan  a:analyze  e:edit  x:del  ?:help  q:quit "
  end

  defp status_bar_help(:tickets) do
    " j/k:nav  Tab:panel  s:start  d:done  r:reset  c:create  e:edit  x:del  ?:help  q:quit "
  end

  defp status_bar_help(:research) do
    " j/k:nav  Tab:panel  ?:help  q:quit "
  end

  defp status_bar_help(:detail) do
    " j/k:scroll  Tab:panel  c:create  e:edit  ?:help  q:quit "
  end
end
