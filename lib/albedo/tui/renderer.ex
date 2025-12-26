defmodule Albedo.TUI.Renderer do
  @moduledoc """
  Renders the TUI interface using ANSI escape codes.
  Implements a lazygit-inspired 3-panel layout.
  """

  alias Albedo.TUI.{State, Terminal}

  @border_chars %{
    top_left: "┌",
    top_right: "┐",
    bottom_left: "└",
    bottom_right: "┘",
    horizontal: "─",
    vertical: "│"
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
    # Kanagawa colors (24-bit true color)
    kanagawa_orange: "\e[38;2;255;160;102m",
    bg_kanagawa_sky_blue: "\e[48;2;127;180;202m"
  }

  @doc """
  Renders the complete UI based on current state.
  """
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
    lines = for row <- 1..height, do: build_help_line(row, state, width, height)
    Enum.intersperse(lines, "\r\n")
  end

  defp build_frame(%{mode: :modal} = state, width, height) do
    base_lines = for row <- 1..height, do: build_line(row, state, width, height)
    modal_lines = build_modal_overlay(state, width, height)

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

  @help_content [
    {:header, "Keyboard Shortcuts"},
    {:blank},
    {:section, "Navigation"},
    {:key, "j / ↓", "Move down"},
    {:key, "k / ↑", "Move up"},
    {:key, "h / ←", "Previous panel"},
    {:key, "l / → / Tab", "Next panel"},
    {:key, "1 / 2 / 3 / 4", "Jump to panel (Projects/Tickets/Research/Detail)"},
    {:blank},
    {:section, "Projects Panel"},
    {:key, "Enter", "Load project tickets"},
    {:key, "n", "Create empty project"},
    {:key, "p", "Plan new project (AI)"},
    {:key, "a", "Analyze codebase (AI)"},
    {:key, "e", "Edit project task"},
    {:key, "x / X", "Delete project"},
    {:key, "R", "Refresh project list"},
    {:blank},
    {:section, "Tickets / Research"},
    {:key, "Enter", "View in detail panel"},
    {:key, "s", "Start ticket (in-progress)"},
    {:key, "d", "Done (completed)"},
    {:key, "r", "Reset ticket to pending"},
    {:key, "c", "Create new ticket"},
    {:key, "e", "Edit ticket"},
    {:key, "x / X", "Delete ticket"},
    {:blank},
    {:section, "Detail Panel"},
    {:key, "j / k", "Scroll content"},
    {:key, "c", "Create new ticket"},
    {:key, "e", "Edit ticket"},
    {:blank},
    {:section, "Edit Mode"},
    {:key, "Tab", "Next field"},
    {:key, "Shift+Tab", "Previous field"},
    {:key, "Enter", "Save changes"},
    {:key, "Esc", "Cancel edit"},
    {:blank},
    {:section, "General"},
    {:key, "?", "Show/hide this help"},
    {:key, "q / Q", "Quit"},
    {:blank},
    {:footer, "Press Esc, Enter, or ? to close"}
  ]

  defp build_help_line(row, _state, width, height) do
    content_start = 3
    content_end = height - 2

    cond do
      row == 1 ->
        title = " Help "

        @colors.bold <>
          @colors.green <> String.pad_trailing(title, width) <> @colors.reset

      row == 2 or row == height - 1 ->
        @colors.dim <> String.duplicate("─", width) <> @colors.reset

      row == height ->
        @colors.dim <>
          String.pad_trailing(" Press Esc, Enter, or ? to close ", width) <> @colors.reset

      row >= content_start and row <= content_end ->
        help_row = row - content_start
        render_help_content_line(help_row, width)

      true ->
        String.duplicate(" ", width)
    end
  end

  defp render_help_content_line(row, width) do
    case Enum.at(@help_content, row) do
      nil ->
        String.duplicate(" ", width)

      {:header, text} ->
        @colors.bold <>
          @colors.green <>
          String.pad_trailing("  " <> text, width) <> @colors.reset

      {:blank} ->
        String.duplicate(" ", width)

      {:section, title} ->
        @colors.bold <>
          @colors.yellow <>
          String.pad_trailing("  " <> title, width) <> @colors.reset

      {:key, key, desc} ->
        padded_key = String.pad_trailing(key, 16)

        "    " <>
          @colors.green <>
          padded_key <>
          @colors.reset <>
          String.pad_trailing(desc, width - 20)

      {:footer, text} ->
        @colors.dim <> String.pad_trailing("  " <> text, width) <> @colors.reset
    end
  end

  defp build_modal_overlay(state, width, height) do
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
      @colors.green <>
        @border_chars.top_left <>
        String.duplicate(@border_chars.horizontal, left_bar) <>
        @colors.bold <>
        @colors.white <>
        title <>
        @colors.reset <>
        @colors.green <>
        String.duplicate(@border_chars.horizontal, right_bar) <>
        @border_chars.top_right <>
        @colors.reset

    left_pad = String.duplicate(" ", start_col)
    right_pad = String.duplicate(" ", max(0, total_width - start_col - modal_width))
    left_pad <> border <> right_pad
  end

  defp build_modal_bottom_border(state, modal_width, start_col, total_width) do
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
        :input -> @colors.green
        :running -> @colors.yellow
        :completed -> @colors.green
        :failed -> @colors.red
      end

    border =
      @colors.green <>
        @border_chars.bottom_left <>
        String.duplicate(@border_chars.horizontal, left_bar) <>
        status_color <>
        hint <>
        @colors.reset <>
        @colors.green <>
        String.duplicate(@border_chars.horizontal, right_bar) <>
        @border_chars.bottom_right <>
        @colors.reset

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
    inner_width = modal_width - 4
    content_lines = build_modal_all_content(state, inner_width, content_height)
    content = Enum.at(content_lines, content_row) || ""

    padded_content = String.pad_trailing(content, inner_width + color_escape_length(content))

    line =
      @colors.green <>
        @border_chars.vertical <>
        @colors.reset <>
        " " <>
        padded_content <>
        " " <>
        @colors.green <>
        @border_chars.vertical <>
        @colors.reset

    left_pad = String.duplicate(" ", start_col)
    right_pad = String.duplicate(" ", max(0, total_width - start_col - modal_width))
    left_pad <> line <> right_pad
  end

  defp build_modal_all_content(state, width, max_lines) do
    data = state.modal_data
    name_label = if state.modal == :plan, do: "Project Name:", else: "Codebase Path:"

    name_lines = wrap_field_text(data.name_buffer, width - 3)
    name_line_count = max(1, length(name_lines))

    task_lines = wrap_field_text(data.task_buffer, width - 3)
    task_line_count = max(1, length(task_lines))

    lines = []

    lines = lines ++ [build_field_label(name_label, data.active_field == :name)]

    lines =
      lines ++
        build_multiline_field(name_lines, data.cursor, width, data.active_field == :name)

    lines = lines ++ [""]
    lines = lines ++ [build_field_label("Task Description:", data.active_field == :task)]

    lines =
      lines ++
        build_multiline_field(task_lines, data.cursor, width, data.active_field == :task)

    form_height = 1 + name_line_count + 1 + 1 + task_line_count

    lines =
      if data.logs != [] or data.phase != :input do
        lines = lines ++ [""]
        log_header = build_log_header(data, state.modal_scroll)
        lines = lines ++ [log_header]

        lines =
          lines ++
            [@colors.dim <> String.duplicate(@border_chars.horizontal, width) <> @colors.reset]

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
    Enum.map(lines, fn line ->
      @colors.dim <> "│ " <> @colors.reset <> String.slice(line, 0, width - 3)
    end)
  end

  defp render_active_field_line({line, idx}, cursor_line_idx, cursor_in_line, width) do
    if idx == cursor_line_idx do
      build_active_field_line_with_cursor(line, cursor_in_line, width)
    else
      @colors.bg_blue <> "▎" <> @colors.reset <> line
    end
  end

  defp build_active_field_line_with_cursor(line, cursor_pos, _width) do
    cursor_pos = min(cursor_pos, String.length(line))
    {before, after_cursor} = String.split_at(line, cursor_pos)

    cursor_char = if after_cursor == "", do: " ", else: String.first(after_cursor)

    after_char =
      if String.length(after_cursor) > 1, do: String.slice(after_cursor, 1..-1//1), else: ""

    @colors.bg_blue <>
      "▎" <>
      @colors.reset <>
      before <>
      @colors.bg_cyan <> cursor_char <> @colors.reset <> after_char
  end

  defp build_log_header(data, _scroll) do
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

    status_color <> @colors.bold <> status_text <> progress_info <> agent_info <> @colors.reset
  end

  defp phase_display(:input), do: {@colors.green, "Progress"}
  defp phase_display(:running), do: {@colors.yellow, "Running..."}
  defp phase_display(:completed), do: {@colors.green, "Completed"}
  defp phase_display(:failed), do: {@colors.red, "Failed"}

  defp build_field_label(label, is_active) do
    label_color = if is_active, do: @colors.green <> @colors.bold, else: @colors.dim
    label_color <> label <> @colors.reset
  end

  defp color_escape_length(str) do
    escape_pattern = ~r/\e\[[0-9;]*m/
    escapes = Regex.scan(escape_pattern, str)
    Enum.reduce(escapes, 0, fn [match], acc -> acc + String.length(match) end)
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
    help_text = mode_help_text(state)
    @colors.dim <> String.pad_trailing(help_text, width) <> @colors.reset
  end

  defp mode_help_text(%{mode: :edit}),
    do: " Tab:next field  Shift+Tab:prev  Enter:save  Esc:cancel "

  defp mode_help_text(%{mode: :input}), do: " Enter:submit  Esc:cancel "
  defp mode_help_text(%{mode: :confirm}), do: " y:confirm  n:cancel  Esc:cancel "
  defp mode_help_text(%{active_panel: panel}), do: status_bar_help(panel)

  defp build_message_line(%{mode: :input} = state, width) do
    prompt = state.input_prompt || ""
    buffer = state.input_buffer || ""
    cursor = state.input_cursor

    {before, after_cursor} = String.split_at(buffer, cursor)
    cursor_char = if after_cursor == "", do: " ", else: String.first(after_cursor)
    after_cursor = if after_cursor == "", do: "", else: String.slice(after_cursor, 1..-1//1)

    input_display =
      prompt <>
        before <>
        @colors.bg_cyan <> cursor_char <> @colors.reset <> @colors.yellow <> after_cursor

    @colors.yellow <>
      String.pad_trailing(
        input_display,
        width + String.length(@colors.bg_cyan) + String.length(@colors.reset) +
          String.length(@colors.yellow)
      ) <> @colors.reset
  end

  defp build_message_line(%{mode: :confirm} = state, width) do
    msg = state.confirm_message || ""
    @colors.red <> @colors.bold <> String.pad_trailing(msg, width) <> @colors.reset
  end

  defp build_message_line(state, width) do
    msg = state.message || ""
    @colors.yellow <> String.pad_trailing(msg, width) <> @colors.reset
  end

  defp build_panel_line(row, state, width, height) do
    left_width = max(30, div(width, 3))
    right_width = width - left_width

    panel_start = 1
    panel_height = height - 2
    section_height = div(panel_height, 3)

    panel_row = row - panel_start + 1

    left_content =
      build_left_panel_char(panel_row, state, left_width, section_height, panel_height)

    right_content = build_right_panel_char(panel_row, state, right_width, panel_height)

    left_content <> right_content
  end

  defp build_left_panel_char(panel_row, state, width, section_height, panel_height) do
    projects_height = section_height
    tickets_height = section_height
    research_height = panel_height - projects_height - tickets_height

    cond do
      panel_row <= 0 or panel_row > panel_height ->
        String.duplicate(" ", width)

      panel_row <= projects_height ->
        build_projects_line(panel_row, state, width, projects_height)

      panel_row <= projects_height + tickets_height ->
        ticket_row = panel_row - projects_height
        build_tickets_line(ticket_row, state, width, tickets_height)

      true ->
        research_row = panel_row - projects_height - tickets_height
        build_research_line(research_row, state, width, research_height)
    end
  end

  defp build_projects_line(row, state, width, height) do
    is_active = state.active_panel == :projects
    border_color = if is_active, do: @colors.kanagawa_orange, else: @colors.white

    cond do
      row == 1 ->
        build_top_border(" [1] Projects ", width, border_color, is_active)

      row == height ->
        build_bottom_border(width, border_color)

      true ->
        content_row = row - 2
        content = build_project_content(content_row, state, width - 2)

        border_color <>
          @border_chars.vertical <>
          @colors.reset <> content <> border_color <> @border_chars.vertical <> @colors.reset
    end
  end

  defp build_project_content(row, state, width) do
    project = Enum.at(state.projects, row)

    if project do
      is_selected = row == state.current_project and state.active_panel == :projects
      build_project_item(project, width, is_selected)
    else
      String.duplicate(" ", width)
    end
  end

  defp build_project_item(project, width, is_selected) do
    bg = if is_selected, do: @colors.bg_kanagawa_sky_blue <> @colors.black, else: ""
    state_indicator = project_state_indicator(project.state)
    id = String.slice(project.id, 0, width - 4)

    bg <> " " <> state_indicator <> " " <> String.pad_trailing(id, width - 3) <> @colors.reset
  end

  defp project_state_indicator("completed"), do: "✓"
  defp project_state_indicator("failed"), do: "✗"
  defp project_state_indicator("paused"), do: "⏸"
  defp project_state_indicator(_), do: "○"

  defp build_tickets_line(row, state, width, height) do
    is_active = state.active_panel == :tickets
    border_color = if is_active, do: @colors.kanagawa_orange, else: @colors.white

    cond do
      row == 1 ->
        build_top_border(" [2] Tickets ", width, border_color, is_active)

      row == height ->
        build_bottom_border(width, border_color)

      true ->
        content_row = row - 2
        content = build_ticket_content(content_row, state, width - 2)

        border_color <>
          @border_chars.vertical <>
          @colors.reset <> content <> border_color <> @border_chars.vertical <> @colors.reset
    end
  end

  defp build_ticket_content(row, state, width) do
    if state.data do
      ticket = Enum.at(state.data.tickets, row)

      if ticket do
        is_selected = row == state.selected_ticket and state.active_panel == :tickets
        build_ticket_item(ticket, width, is_selected)
      else
        String.duplicate(" ", width)
      end
    else
      if row == 0 do
        msg = "No project selected"
        @colors.dim <> String.pad_trailing(msg, width) <> @colors.reset
      else
        String.duplicate(" ", width)
      end
    end
  end

  defp build_ticket_item(ticket, width, is_selected) do
    bg = if is_selected, do: @colors.bg_kanagawa_sky_blue <> @colors.black, else: ""
    status_ind = status_indicator(ticket.status)

    points = if ticket.estimate, do: " [#{ticket.estimate}]", else: ""
    points_len = String.length(points)
    prefix_len = 3
    title_width = max(0, width - prefix_len - points_len)
    title = String.pad_trailing(String.slice(ticket.title, 0, title_width), title_width)

    bg <> " " <> status_ind <> " " <> title <> points <> @colors.reset
  end

  defp build_research_line(row, state, width, height) do
    is_active = state.active_panel == :research
    border_color = if is_active, do: @colors.kanagawa_orange, else: @colors.white

    cond do
      row == 1 ->
        build_top_border(" [3] Research ", width, border_color, is_active)

      row == height ->
        build_bottom_border(width, border_color)

      true ->
        content_row = row - 2
        content = build_research_content(content_row, state, width - 2)

        border_color <>
          @border_chars.vertical <>
          @colors.reset <> content <> border_color <> @border_chars.vertical <> @colors.reset
    end
  end

  defp build_research_content(row, %{research_files: []} = state, width) do
    build_empty_research_message(row, state, width)
  end

  defp build_research_content(row, state, width) do
    case Enum.at(state.research_files, row) do
      nil ->
        String.duplicate(" ", width)

      file ->
        is_selected = row == state.selected_file and state.active_panel == :research
        build_research_item(file, width, is_selected)
    end
  end

  defp build_empty_research_message(0, state, width) do
    msg = if state.data, do: "No research files", else: "Select a project"
    @colors.dim <> String.pad_trailing(msg, width) <> @colors.reset
  end

  defp build_empty_research_message(_row, _state, width) do
    String.duplicate(" ", width)
  end

  defp build_research_item(file, width, is_selected) do
    bg = if is_selected, do: @colors.bg_kanagawa_sky_blue <> @colors.black, else: ""
    type_indicator = if file.type == :markdown, do: "md", else: "js"
    name = String.slice(file.name, 0, width - 5)

    bg <> " " <> type_indicator <> " " <> String.pad_trailing(name, width - 4) <> @colors.reset
  end

  defp build_right_panel_char(panel_row, state, width, height) do
    is_active = state.active_panel == :detail or state.mode == :edit
    border_color = if is_active, do: @colors.kanagawa_orange, else: @colors.white
    title = if state.mode == :edit, do: " Edit Ticket ", else: " [4] Detail "

    cond do
      panel_row <= 0 or panel_row > height ->
        String.duplicate(" ", width)

      panel_row == 1 ->
        build_top_border(title, width, border_color, is_active)

      panel_row == height ->
        build_bottom_border(width, border_color)

      true ->
        content_row = panel_row - 2
        content = build_detail_content(content_row, state, width - 2, height - 2)

        border_color <>
          @border_chars.vertical <>
          @colors.reset <> content <> border_color <> @border_chars.vertical <> @colors.reset
    end
  end

  defp build_detail_content(row, state, width, height) do
    cond do
      state.data == nil ->
        if row == 0 do
          @colors.dim <> String.pad_trailing("Select a project", width) <> @colors.reset
        else
          String.duplicate(" ", width)
        end

      state.mode == :edit ->
        build_edit_content_line(row, state, width)

      state.active_panel == :research ->
        build_research_file_content_line(row, state, width, height)

      state.active_panel == :detail and state.detail_content == :research ->
        build_research_file_content_line(row, state, width, height)

      true ->
        build_view_content_line(row, state, width, height)
    end
  end

  defp build_edit_content_line(row, state, width) do
    case State.current_ticket(state) do
      nil -> String.duplicate(" ", width)
      ticket -> build_edit_row(row, state, ticket, width)
    end
  end

  defp build_edit_row(0, _state, ticket, width) do
    @colors.bold <>
      @colors.green <> String.pad_trailing("Editing ##{ticket.id}", width) <> @colors.reset
  end

  defp build_edit_row(1, _state, _ticket, width), do: String.duplicate(" ", width)

  defp build_edit_row(row, state, ticket, width) do
    fields = State.editable_fields()
    total_field_rows = length(fields) * 2 + 2

    cond do
      row <= total_field_rows ->
        render_field_row(row, state, ticket, fields, width)

      row == total_field_rows + 1 ->
        @colors.dim <>
          String.pad_trailing("Tab/Shift+Tab:nav  Enter:save  Esc:cancel", width) <>
          @colors.reset

      true ->
        String.duplicate(" ", width)
    end
  end

  defp render_field_row(row, state, ticket, fields, width) do
    field_idx = div(row - 2, 2)
    is_label_row = rem(row - 2, 2) == 0

    case Enum.at(fields, field_idx) do
      nil ->
        String.duplicate(" ", width)

      field ->
        is_active = state.edit_field == field
        render_field_content(is_label_row, state, ticket, field, width, is_active)
    end
  end

  defp render_field_content(true, _state, _ticket, field, width, is_active) do
    build_field_label_line(field, width, is_active)
  end

  defp render_field_content(false, state, ticket, field, width, is_active) do
    build_field_input_line(state, ticket, field, width, is_active)
  end

  defp build_field_label_line(field, width, is_active) do
    label = field_label(field)

    if is_active do
      @colors.green <> @colors.bold <> String.pad_trailing(label, width) <> @colors.reset
    else
      @colors.dim <> String.pad_trailing(label, width) <> @colors.reset
    end
  end

  defp build_field_input_line(state, ticket, field, width, is_active) do
    value =
      if is_active do
        state.edit_buffer || ""
      else
        get_display_value(ticket, field)
      end

    if is_active do
      build_input_field_line(value, state.edit_cursor, width)
    else
      @colors.dim <>
        "│ " <> @colors.reset <> String.pad_trailing(String.slice(value, 0, width - 3), width - 2)
    end
  end

  defp build_input_field_line(value, cursor, width) do
    cursor = min(cursor, String.length(value))
    {before, after_cursor} = String.split_at(value, cursor)

    max_visible = width - 3
    visible_before = String.slice(before, -max(0, max_visible - 1), max_visible - 1)
    cursor_char = if after_cursor == "", do: " ", else: String.first(after_cursor)

    after_char =
      if String.length(after_cursor) > 1, do: String.slice(after_cursor, 1..-1//1), else: ""

    remaining = max_visible - String.length(visible_before) - 1
    visible_after = String.slice(after_char, 0, max(0, remaining))

    content =
      @colors.bg_blue <>
        "▎" <>
        @colors.reset <>
        visible_before <>
        @colors.bg_cyan <> cursor_char <> @colors.reset <> visible_after

    used = String.length(visible_before) + 1 + String.length(visible_after) + 2
    padding = max(0, width - used)

    content <> String.duplicate(" ", padding)
  end

  defp build_view_content_line(row, state, width, _height) do
    ticket = State.current_ticket(state)

    if ticket == nil do
      if row == 0 do
        @colors.dim <> String.pad_trailing("No ticket selected", width) <> @colors.reset
      else
        String.duplicate(" ", width)
      end
    else
      lines = build_ticket_lines(ticket, width - 8)
      scroll = state.detail_scroll

      visible_line = Enum.at(lines, row + scroll)

      if visible_line do
        render_detail_line_to_string(visible_line, width)
      else
        String.duplicate(" ", width)
      end
    end
  end

  defp build_research_file_content_line(row, state, width, _height) do
    file = State.current_research_file(state)

    if file == nil do
      if row == 0 do
        @colors.dim <> String.pad_trailing("No file selected", width) <> @colors.reset
      else
        String.duplicate(" ", width)
      end
    else
      lines = build_file_content_lines(file, width - 8)
      scroll = state.detail_scroll

      visible_line = Enum.at(lines, row + scroll)

      if visible_line do
        render_file_line_to_string(visible_line, width)
      else
        String.duplicate(" ", width)
      end
    end
  end

  defp build_file_content_lines(file, width) do
    case File.read(file.path) do
      {:ok, content} ->
        lines = [{:header, file.name}, {:blank}]

        content_lines =
          content
          |> String.split("\n")
          |> Enum.flat_map(&parse_file_line(&1, file.type, width))

        lines ++ content_lines

      {:error, reason} ->
        [{:header, file.name}, {:blank}, {:error, "Error reading file: #{inspect(reason)}"}]
    end
  end

  defp parse_file_line(line, :markdown, width) do
    cond do
      String.starts_with?(line, "# ") ->
        text = String.trim_leading(line, "# ")
        wrap_text(text, width) |> Enum.map(&{:md_h1, &1})

      String.starts_with?(line, "## ") ->
        text = String.trim_leading(line, "## ")
        wrap_text(text, width) |> Enum.map(&{:md_h2, &1})

      String.starts_with?(line, "### ") ->
        text = String.trim_leading(line, "### ")
        wrap_text(text, width) |> Enum.map(&{:md_h3, &1})

      String.starts_with?(line, "- ") or String.starts_with?(line, "* ") ->
        wrap_text(line, width) |> Enum.map(&{:md_list, &1})

      String.starts_with?(line, "```") ->
        [{:md_code_fence, String.slice(line, 0, width)}]

      line == "" ->
        [{:blank}]

      true ->
        wrap_text(line, width) |> Enum.map(&{:text, &1})
    end
  end

  defp parse_file_line(line, :json, width) do
    wrap_text(line, width) |> Enum.map(&{:json_line, &1})
  end

  defp parse_file_line(line, _type, width) do
    wrap_text(line, width) |> Enum.map(&{:text, &1})
  end

  defp render_file_line_to_string({:header, text}, width) do
    content_width = width - 1
    " " <> @colors.bold <> @colors.green <> pad_content(text, content_width) <> @colors.reset
  end

  defp render_file_line_to_string({:blank}, width) do
    String.duplicate(" ", width)
  end

  defp render_file_line_to_string({:md_h1, text}, width) do
    content_width = width - 1
    " " <> @colors.bold <> @colors.green <> pad_content(text, content_width) <> @colors.reset
  end

  defp render_file_line_to_string({:md_h2, text}, width) do
    content_width = width - 1
    " " <> @colors.bold <> @colors.yellow <> pad_content(text, content_width) <> @colors.reset
  end

  defp render_file_line_to_string({:md_h3, text}, width) do
    content_width = width - 1
    " " <> @colors.bold <> pad_content(text, content_width) <> @colors.reset
  end

  defp render_file_line_to_string({:md_list, text}, width) do
    content_width = width - 1
    " " <> @colors.green <> pad_content(text, content_width) <> @colors.reset
  end

  defp render_file_line_to_string({:md_code_fence, text}, width) do
    content_width = width - 1
    " " <> @colors.dim <> pad_content(text, content_width) <> @colors.reset
  end

  defp render_file_line_to_string({:json_line, text}, width) do
    content_width = width - 1
    " " <> @colors.dim <> pad_content(text, content_width) <> @colors.reset
  end

  defp render_file_line_to_string({:text, text}, width) do
    content_width = width - 1
    " " <> pad_content(text, content_width)
  end

  defp render_file_line_to_string({:error, text}, width) do
    content_width = width - 1
    " " <> @colors.red <> pad_content(text, content_width) <> @colors.reset
  end

  defp pad_content(text, width) do
    String.pad_trailing(String.slice(text, 0, width), width)
  end

  defp render_detail_line_to_string({:header, text}, width) do
    content_width = width - 1
    " " <> @colors.bold <> @colors.green <> pad_content(text, content_width) <> @colors.reset
  end

  defp render_detail_line_to_string({:blank}, width) do
    String.duplicate(" ", width)
  end

  defp render_detail_line_to_string({:section, title}, width) do
    content_width = width - 1
    " " <> @colors.green <> @colors.bold <> pad_content(title, content_width) <> @colors.reset
  end

  defp render_detail_line_to_string({:subsection, title}, width) do
    content_width = width - 3
    "   " <> @colors.dim <> pad_content(title, content_width) <> @colors.reset
  end

  defp render_detail_line_to_string({:field, label, value, color}, width) do
    padded_label = String.pad_trailing(label <> ":", 12)
    value_width = max(0, width - 13)
    sliced_value = String.slice(value, 0, value_width)

    " " <>
      @colors.dim <>
      padded_label <>
      @colors.reset <> color <> String.pad_trailing(sliced_value, value_width) <> @colors.reset
  end

  defp render_detail_line_to_string({:text, text}, width) do
    content_width = width - 1
    " " <> pad_content(text, content_width)
  end

  defp render_detail_line_to_string({:file, path, color}, width) do
    path_width = max(0, width - 5)
    "     " <> color <> pad_content(path, path_width) <> @colors.reset
  end

  defp build_top_border(title, width, border_color, is_active) do
    title_color = if is_active, do: @colors.bold <> @colors.green, else: @colors.white
    bar_width = width - 2
    title_len = String.length(title)
    left_bar = div(bar_width - title_len, 2)
    right_bar = bar_width - title_len - left_bar

    border_color <>
      @border_chars.top_left <>
      String.duplicate(@border_chars.horizontal, left_bar) <>
      title_color <>
      title <>
      border_color <>
      String.duplicate(@border_chars.horizontal, right_bar) <>
      @border_chars.top_right <> @colors.reset
  end

  defp build_bottom_border(width, border_color) do
    border_color <>
      @border_chars.bottom_left <>
      String.duplicate(@border_chars.horizontal, width - 2) <>
      @border_chars.bottom_right <> @colors.reset
  end

  defp status_indicator(:pending), do: "○"
  defp status_indicator(:in_progress), do: "●"
  defp status_indicator(:completed), do: "✓"

  defp status_color(:pending), do: @colors.dim
  defp status_color(:in_progress), do: @colors.yellow
  defp status_color(:completed), do: @colors.green

  defp field_label(:title), do: "Title:"
  defp field_label(:description), do: "Description:"
  defp field_label(:type), do: "Type (feature/enhancement/bugfix/chore/docs/test):"
  defp field_label(:priority), do: "Priority (urgent/high/medium/low/none):"
  defp field_label(:estimate), do: "Points (1-13):"
  defp field_label(:labels), do: "Labels (comma-separated):"
  defp field_label(_), do: "Field:"

  defp get_display_value(ticket, :title), do: ticket.title || ""
  defp get_display_value(ticket, :description), do: ticket.description || ""
  defp get_display_value(ticket, :type), do: to_string(ticket.type)
  defp get_display_value(ticket, :priority), do: to_string(ticket.priority)

  defp get_display_value(ticket, :estimate),
    do: if(ticket.estimate, do: to_string(ticket.estimate), else: "")

  defp get_display_value(ticket, :labels), do: Enum.join(ticket.labels, ", ")
  defp get_display_value(_, _), do: ""

  defp build_ticket_lines(ticket, width) do
    []
    |> add_header_lines(ticket)
    |> add_metadata_lines(ticket)
    |> add_description_lines(ticket, width)
    |> add_acceptance_criteria_lines(ticket, width)
    |> add_implementation_notes_lines(ticket, width)
    |> add_files_lines(ticket)
    |> add_dependencies_lines(ticket)
  end

  defp add_header_lines(lines, ticket) do
    lines ++ [{:header, "##{ticket.id}: #{ticket.title}"}, {:blank}]
  end

  defp add_metadata_lines(lines, ticket) do
    lines
    |> then(&(&1 ++ [{:field, "Status", to_string(ticket.status), status_color(ticket.status)}]))
    |> then(&(&1 ++ [{:field, "Type", to_string(ticket.type), ""}]))
    |> then(
      &(&1 ++ [{:field, "Priority", to_string(ticket.priority), priority_color(ticket.priority)}])
    )
    |> maybe_add_points(ticket)
    |> maybe_add_labels(ticket)
  end

  defp maybe_add_points(lines, %{estimate: nil}), do: lines

  defp maybe_add_points(lines, ticket) do
    lines ++ [{:field, "Points", to_string(ticket.estimate), ""}]
  end

  defp maybe_add_labels(lines, %{labels: []}), do: lines

  defp maybe_add_labels(lines, ticket) do
    lines ++ [{:field, "Labels", Enum.join(ticket.labels, ", "), @colors.magenta}]
  end

  defp add_description_lines(lines, %{description: nil}, _width), do: lines
  defp add_description_lines(lines, %{description: ""}, _width), do: lines

  defp add_description_lines(lines, ticket, width) do
    wrapped = wrap_text(ticket.description, width - 2)
    text_lines = Enum.map(wrapped, &{:text, &1})
    lines ++ [{:blank}, {:section, "Description"}] ++ text_lines
  end

  defp add_acceptance_criteria_lines(lines, %{acceptance_criteria: []}, _width), do: lines

  defp add_acceptance_criteria_lines(lines, ticket, width) do
    criteria_lines =
      ticket.acceptance_criteria
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {criterion, idx} ->
        wrapped = wrap_text("#{idx}. #{criterion}", width - 2)
        Enum.map(wrapped, &{:text, &1})
      end)

    lines ++ [{:blank}, {:section, "Acceptance Criteria"}] ++ criteria_lines
  end

  defp add_implementation_notes_lines(lines, %{implementation_notes: nil}, _width), do: lines
  defp add_implementation_notes_lines(lines, %{implementation_notes: ""}, _width), do: lines

  defp add_implementation_notes_lines(lines, ticket, width) do
    wrapped = wrap_text(ticket.implementation_notes, width - 2)
    text_lines = Enum.map(wrapped, &{:text, &1})
    lines ++ [{:blank}, {:section, "Implementation Notes"}] ++ text_lines
  end

  defp add_files_lines(lines, ticket) do
    has_create = ticket.files.create != []
    has_modify = ticket.files.modify != []

    if has_create or has_modify do
      lines
      |> then(&(&1 ++ [{:blank}, {:section, "Files"}]))
      |> maybe_add_create_files(ticket.files.create)
      |> maybe_add_modify_files(ticket.files.modify)
    else
      lines
    end
  end

  defp maybe_add_create_files(lines, []), do: lines

  defp maybe_add_create_files(lines, files) do
    file_lines = Enum.map(files, &{:file, &1, @colors.green})
    lines ++ [{:subsection, "Create:"}] ++ file_lines
  end

  defp maybe_add_modify_files(lines, []), do: lines

  defp maybe_add_modify_files(lines, files) do
    file_lines = Enum.map(files, &{:file, &1, @colors.yellow})
    lines ++ [{:subsection, "Modify:"}] ++ file_lines
  end

  defp add_dependencies_lines(lines, ticket) do
    has_blocked_by = ticket.dependencies.blocked_by != []
    has_blocks = ticket.dependencies.blocks != []

    if has_blocked_by or has_blocks do
      lines
      |> then(&(&1 ++ [{:blank}, {:section, "Dependencies"}]))
      |> maybe_add_blocked_by(ticket.dependencies.blocked_by)
      |> maybe_add_blocks(ticket.dependencies.blocks)
    else
      lines
    end
  end

  defp maybe_add_blocked_by(lines, []), do: lines

  defp maybe_add_blocked_by(lines, blocked_by) do
    blocked = Enum.join(blocked_by, ", ")
    lines ++ [{:field, "Blocked by", blocked, @colors.red}]
  end

  defp maybe_add_blocks(lines, []), do: lines

  defp maybe_add_blocks(lines, blocks_list) do
    blocks = Enum.join(blocks_list, ", ")
    lines ++ [{:field, "Blocks", blocks, @colors.yellow}]
  end

  defp priority_color(:urgent), do: @colors.red
  defp priority_color(:high), do: @colors.yellow
  defp priority_color(:medium), do: ""
  defp priority_color(:low), do: @colors.dim
  defp priority_color(:none), do: @colors.dim

  defp wrap_text(text, width) when is_binary(text) and width > 0 do
    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line(&1, width))
  end

  defp wrap_text(_, _), do: []

  defp wrap_line("", _width), do: [""]

  defp wrap_line(line, width) do
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
