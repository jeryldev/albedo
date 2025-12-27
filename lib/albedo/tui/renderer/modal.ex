defmodule Albedo.TUI.Renderer.Modal do
  @moduledoc """
  Renders modal overlays for plan/analyze operations.
  """

  alias Albedo.TUI.Renderer.Utils

  def build_modal_overlay(state, width, height) do
    modal_width = min(100, width - 4)
    modal_height = min(height - 4, 30)
    start_col = div(width - modal_width, 2)
    start_row = div(height - modal_height, 2)
    end_row = start_row + modal_height - 1

    for row <- 1..height do
      cond do
        row < start_row or row > end_row ->
          nil

        row == start_row ->
          build_modal_top_border(state, modal_width, start_col, width)

        row == end_row ->
          build_modal_bottom_border(state, modal_width, start_col, width)

        true ->
          content_row = row - start_row - 1

          build_modal_content_line(
            state,
            content_row,
            modal_width,
            modal_height - 2,
            start_col,
            width
          )
      end
    end
  end

  defp build_modal_top_border(state, modal_width, start_col, total_width) do
    colors = Utils.colors()
    border_chars = Utils.border_chars()
    type_label = if state.modal == :plan, do: "Plan New Project", else: "Analyze Codebase"

    title =
      case state.modal_data.phase do
        :input -> " #{type_label} "
        _ -> " #{type_label}: #{state.modal_data.name} "
      end

    title = String.slice(title, 0, modal_width - 4)

    bar_width = modal_width - 2
    title_len = String.length(title)
    left_bar = div(bar_width - title_len, 2)
    right_bar = bar_width - title_len - left_bar

    border =
      colors.green <>
        border_chars.top_left <>
        String.duplicate(border_chars.horizontal, left_bar) <>
        colors.bold <>
        colors.white <>
        title <>
        colors.reset <>
        colors.green <>
        String.duplicate(border_chars.horizontal, right_bar) <>
        border_chars.top_right <>
        colors.reset

    left_pad = String.duplicate(" ", start_col)
    right_pad = String.duplicate(" ", max(0, total_width - start_col - modal_width))
    left_pad <> border <> right_pad
  end

  defp build_modal_bottom_border(state, modal_width, start_col, total_width) do
    colors = Utils.colors()
    border_chars = Utils.border_chars()

    hint =
      case state.modal_data.phase do
        :input -> " Tab:switch field  Enter:submit  Esc:cancel "
        :running -> " Running... "
        :completed -> " Press Enter or Esc to close "
        :failed -> " Press Enter or Esc to close "
      end

    hint = String.slice(hint, 0, modal_width - 4)
    bar_width = modal_width - 2
    hint_len = String.length(hint)
    left_bar = div(bar_width - hint_len, 2)
    right_bar = bar_width - hint_len - left_bar

    status_color =
      case state.modal_data.phase do
        :input -> colors.green
        :running -> colors.yellow
        :completed -> colors.green
        :failed -> colors.red
      end

    border =
      colors.green <>
        border_chars.bottom_left <>
        String.duplicate(border_chars.horizontal, left_bar) <>
        status_color <>
        hint <>
        colors.reset <>
        colors.green <>
        String.duplicate(border_chars.horizontal, right_bar) <>
        border_chars.bottom_right <>
        colors.reset

    left_pad = String.duplicate(" ", start_col)
    right_pad = String.duplicate(" ", max(0, total_width - start_col - modal_width))
    left_pad <> border <> right_pad
  end

  defp build_modal_content_line(
         state,
         content_row,
         modal_width,
         content_height,
         start_col,
         total_width
       ) do
    colors = Utils.colors()
    border_chars = Utils.border_chars()
    inner_width = modal_width - 4
    content_lines = build_modal_all_content(state, inner_width, content_height)
    content = Enum.at(content_lines, content_row) || ""

    padded_content =
      String.pad_trailing(content, inner_width + Utils.color_escape_length(content))

    line =
      colors.green <>
        border_chars.vertical <>
        colors.reset <>
        " " <>
        padded_content <>
        " " <>
        colors.green <>
        border_chars.vertical <>
        colors.reset

    left_pad = String.duplicate(" ", start_col)
    right_pad = String.duplicate(" ", max(0, total_width - start_col - modal_width))
    left_pad <> line <> right_pad
  end

  defp build_modal_all_content(state, width, max_lines) do
    colors = Utils.colors()
    border_chars = Utils.border_chars()
    data = state.modal_data
    is_analyze = state.modal == :analyze
    name_label = if is_analyze, do: "Codebase Path:", else: "Project Name:"

    name_lines = wrap_field_text(data.name_buffer, width - 3)
    name_line_count = max(1, length(name_lines))

    title_lines = if is_analyze, do: wrap_field_text(data.title_buffer, width - 3), else: []
    title_line_count = if is_analyze, do: max(1, length(title_lines)), else: 0

    task_lines = wrap_field_text(data.task_buffer, width - 3)
    task_line_count = max(1, length(task_lines))

    lines = []

    lines = lines ++ [build_field_label(name_label, data.active_field == :name)]

    lines =
      lines ++
        build_multiline_field(name_lines, data.cursor, width, data.active_field == :name)

    lines =
      if is_analyze do
        lines = lines ++ [""]

        lines =
          lines ++ [build_field_label("Project Name (optional):", data.active_field == :title)]

        lines ++
          build_multiline_field(title_lines, data.cursor, width, data.active_field == :title)
      else
        lines
      end

    lines = lines ++ [""]
    lines = lines ++ [build_field_label("Task Description:", data.active_field == :task)]

    lines =
      lines ++
        build_multiline_field(task_lines, data.cursor, width, data.active_field == :task)

    form_height =
      1 + name_line_count + if(is_analyze, do: 1 + 1 + title_line_count, else: 0) + 1 + 1 +
        task_line_count

    lines =
      if data.logs != [] or data.phase != :input do
        lines = lines ++ [""]
        log_header = build_log_header(data, state.modal_scroll)
        lines = lines ++ [log_header]

        lines =
          lines ++
            [colors.dim <> String.duplicate(border_chars.horizontal, width) <> colors.reset]

        logs_start = form_height + 3
        available_log_lines = max(1, max_lines - logs_start)

        visible_logs =
          data.logs
          |> Enum.drop(state.modal_scroll)
          |> Enum.take(available_log_lines)
          |> Enum.map(&String.slice(&1, 0, width))

        lines ++ visible_logs
      else
        lines
      end

    lines
  end

  defp wrap_field_text("", _width), do: [""]

  defp wrap_field_text(text, width) when width > 0 do
    text
    |> String.graphemes()
    |> Enum.chunk_every(width)
    |> Enum.map(&Enum.join/1)
  end

  defp wrap_field_text(_text, _width), do: [""]

  defp build_multiline_field([], cursor, width, is_active) do
    build_multiline_field([""], cursor, width, is_active)
  end

  defp build_multiline_field(lines, cursor, width, true = _is_active) do
    total_text = Enum.join(lines, "")
    line_width = width - 3
    cursor = min(cursor, String.length(total_text))

    cursor_line_idx = div(cursor, max(1, line_width))
    cursor_in_line = rem(cursor, max(1, line_width))

    lines
    |> Enum.with_index()
    |> Enum.map(&render_active_field_line(&1, cursor_line_idx, cursor_in_line, width))
  end

  defp build_multiline_field(lines, _cursor, width, false = _is_active) do
    colors = Utils.colors()

    Enum.map(lines, fn line ->
      colors.dim <> "│ " <> colors.reset <> String.slice(line, 0, width - 3)
    end)
  end

  defp render_active_field_line({line, idx}, cursor_line_idx, cursor_in_line, width) do
    colors = Utils.colors()

    if idx == cursor_line_idx do
      build_active_field_line_with_cursor(line, cursor_in_line, width)
    else
      colors.bg_blue <> "▎" <> colors.reset <> line
    end
  end

  defp build_active_field_line_with_cursor(line, cursor_pos, _width) do
    colors = Utils.colors()
    cursor_pos = min(cursor_pos, String.length(line))
    {before, after_cursor} = String.split_at(line, cursor_pos)

    cursor_char = if after_cursor == "", do: " ", else: String.first(after_cursor)

    after_char =
      if String.length(after_cursor) > 1, do: String.slice(after_cursor, 1..-1//1), else: ""

    colors.bg_blue <>
      "▎" <>
      colors.reset <>
      before <>
      colors.bg_cyan <> cursor_char <> colors.reset <> after_char
  end

  defp build_log_header(data, _scroll) do
    colors = Utils.colors()
    {status_color, status_text} = phase_display(data.phase)

    progress_info =
      if data.phase == :running and data.total_agents > 0 do
        " (#{data.current_agent}/#{data.total_agents})"
      else
        ""
      end

    agent_info =
      if data.phase == :running and data.agent_name do
        " #{data.agent_name}"
      else
        ""
      end

    status_color <> colors.bold <> status_text <> progress_info <> agent_info <> colors.reset
  end

  defp phase_display(:input) do
    colors = Utils.colors()
    {colors.green, "Progress"}
  end

  defp phase_display(:running) do
    colors = Utils.colors()
    {colors.yellow, "Running..."}
  end

  defp phase_display(:completed) do
    colors = Utils.colors()
    {colors.green, "Completed"}
  end

  defp phase_display(:failed) do
    colors = Utils.colors()
    {colors.red, "Failed"}
  end

  defp build_field_label(label, is_active) do
    colors = Utils.colors()
    label_color = if is_active, do: colors.green <> colors.bold, else: colors.dim
    label_color <> label <> colors.reset
  end
end
