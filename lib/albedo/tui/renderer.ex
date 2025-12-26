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
    vertical: "│",
    t_right: "├",
    t_left: "┤",
    t_down: "┬",
    t_up: "┴",
    cross: "┼"
  }

  @colors %{
    reset: "\e[0m",
    bold: "\e[1m",
    dim: "\e[2m",
    red: "\e[31m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    white: "\e[37m",
    bg_blue: "\e[44m",
    bg_cyan: "\e[46m"
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

  defp build_frame(state, width, height) do
    lines = for row <- 1..height, do: build_line(row, state, width, height)
    Enum.intersperse(lines, "\r\n")
  end

  defp build_line(row, state, width, height) do
    cond do
      row == 1 ->
        build_header_line(state, width)

      row == 2 ->
        String.duplicate(" ", width)

      row == height - 1 ->
        build_status_line(state, width)

      row == height ->
        build_message_line(state, width)

      true ->
        build_panel_line(row, state, width, height)
    end
  end

  defp build_header_line(state, width) do
    title = " Albedo TUI "

    project_info =
      if state.data, do: " │ #{state.data.project_id}", else: ""

    header = title <> project_info

    @colors.bold <> @colors.cyan <> String.pad_trailing(header, width) <> @colors.reset
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

    panel_start = 3
    panel_height = height - 4
    projects_height = div(panel_height, 3)

    panel_row = row - panel_start + 1

    left_content =
      build_left_panel_char(panel_row, state, left_width, projects_height, panel_height)

    right_content = build_right_panel_char(panel_row, state, right_width, panel_height)

    left_content <> right_content
  end

  defp build_left_panel_char(panel_row, state, width, projects_height, panel_height) do
    tickets_height = panel_height - projects_height

    cond do
      panel_row <= 0 or panel_row > panel_height ->
        String.duplicate(" ", width)

      panel_row <= projects_height ->
        build_projects_line(panel_row, state, width, projects_height)

      true ->
        ticket_row = panel_row - projects_height
        build_tickets_line(ticket_row, state, width, tickets_height)
    end
  end

  defp build_projects_line(row, state, width, height) do
    is_active = state.active_panel == :projects
    border_color = if is_active, do: @colors.cyan, else: @colors.dim

    cond do
      row == 1 ->
        build_top_border(" Projects ", width, border_color, is_active)

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
    bg = if is_selected, do: @colors.bg_blue, else: ""
    state_color = project_state_color(project.state)
    indicator = if is_selected, do: "▶ ", else: "  "
    id = String.slice(project.id, 0, width - 4)

    bg <> indicator <> state_color <> String.pad_trailing(id, width - 2) <> @colors.reset
  end

  defp build_tickets_line(row, state, width, height) do
    is_active = state.active_panel == :tickets
    border_color = if is_active, do: @colors.cyan, else: @colors.dim

    cond do
      row == 1 ->
        build_top_border(" Tickets ", width, border_color, is_active)

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
    bg = if is_selected, do: @colors.bg_blue, else: ""
    status_ind = status_indicator(ticket.status)
    status_col = status_color(ticket.status)

    points = if ticket.estimate, do: "[#{ticket.estimate}]", else: "   "
    id_str = String.pad_leading(ticket.id, 2)
    title_width = width - 10
    title = String.slice(ticket.title, 0, title_width)

    bg <>
      id_str <>
      " " <>
      status_col <>
      status_ind <>
      @colors.reset <>
      bg <>
      " " <>
      String.pad_trailing(title, title_width) <>
      " " <>
      @colors.dim <> points <> @colors.reset
  end

  defp build_right_panel_char(panel_row, state, width, height) do
    is_active = state.active_panel == :detail or state.mode == :edit
    border_color = if is_active, do: @colors.cyan, else: @colors.dim
    title = if state.mode == :edit, do: " Edit Ticket ", else: " Detail "

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
      @colors.cyan <> String.pad_trailing("Editing ##{ticket.id}", width) <> @colors.reset
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
      @colors.cyan <> @colors.bold <> String.pad_trailing(label, width) <> @colors.reset
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
      lines = build_ticket_lines(ticket, width - 2)
      scroll = state.detail_scroll

      visible_line = Enum.at(lines, row + scroll)

      if visible_line do
        render_detail_line_to_string(visible_line, width)
      else
        String.duplicate(" ", width)
      end
    end
  end

  defp render_detail_line_to_string({:header, text}, width) do
    @colors.bold <> @colors.cyan <> String.pad_trailing(text, width) <> @colors.reset
  end

  defp render_detail_line_to_string({:blank}, width) do
    String.duplicate(" ", width)
  end

  defp render_detail_line_to_string({:section, title}, width) do
    @colors.cyan <> @colors.bold <> String.pad_trailing(title, width) <> @colors.reset
  end

  defp render_detail_line_to_string({:subsection, title}, width) do
    @colors.dim <> String.pad_trailing("  " <> title, width) <> @colors.reset
  end

  defp render_detail_line_to_string({:field, label, value, color}, width) do
    padded_label = String.pad_trailing(label <> ":", 12)

    @colors.dim <>
      padded_label <>
      @colors.reset <> color <> String.pad_trailing(value, width - 12) <> @colors.reset
  end

  defp render_detail_line_to_string({:text, text}, width) do
    String.pad_trailing(text, width)
  end

  defp render_detail_line_to_string({:file, path, color}, width) do
    "    " <> color <> String.pad_trailing(path, width - 4) <> @colors.reset
  end

  defp build_top_border(title, width, border_color, is_active) do
    title_color = if is_active, do: @colors.bold <> @colors.cyan, else: @colors.dim
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

  defp project_state_color("completed"), do: @colors.green
  defp project_state_color("failed"), do: @colors.red
  defp project_state_color("paused"), do: @colors.yellow
  defp project_state_color(_), do: @colors.dim

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
    " j/k:nav  Tab:panel  Enter:select  n:new  e:edit  x:delete  R:refresh  q:quit "
  end

  defp status_bar_help(:tickets) do
    " j/k:nav  Tab:panel  s:start  d:done  r:reset  a:add  e:edit  x:delete  q:quit "
  end

  defp status_bar_help(:detail) do
    " j/k:scroll  Tab:panel  e:edit  q:quit "
  end
end
