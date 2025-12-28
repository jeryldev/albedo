defmodule Albedo.TUI.Renderer.Detail do
  @moduledoc """
  Renders the detail panel: ticket details, edit mode, and file content.
  """

  alias Albedo.TUI.{Renderer.Utils, State}

  def build_right_panel_char(panel_row, state, width, height) do
    is_active = detail_panel_active?(state)
    border_color = panel_border_color(is_active)
    title = panel_title(state.mode)

    build_panel_row(panel_row, state, width, height, is_active, border_color, title)
  end

  defp detail_panel_active?(state) do
    (state.active_panel == :detail or state.mode == :edit) and state.mode != :modal
  end

  defp panel_border_color(true), do: Utils.colors().kanagawa_orange
  defp panel_border_color(false), do: Utils.colors().white

  defp panel_title(:edit), do: " Edit Ticket "
  defp panel_title(_), do: " [4] Detail "

  defp build_panel_row(row, _state, width, height, _is_active, _border_color, _title)
       when row <= 0 or row > height do
    String.duplicate(" ", width)
  end

  defp build_panel_row(1, _state, width, _height, is_active, border_color, title) do
    Utils.build_top_border(title, width, border_color, is_active)
  end

  defp build_panel_row(row, _state, width, height, is_active, border_color, _title)
       when row == height do
    Utils.build_bottom_border(width, border_color, is_active)
  end

  defp build_panel_row(row, state, width, height, is_active, border_color, _title) do
    colors = Utils.colors()
    border_chars = Utils.border_chars(is_active)
    content_row = row - 2
    content = build_detail_content(content_row, state, width - 2, height - 2)

    border_color <>
      border_chars.vertical <>
      colors.reset <> content <> border_color <> border_chars.vertical <> colors.reset
  end

  defp build_detail_content(row, state, width, height) do
    colors = Utils.colors()

    cond do
      state.data == nil ->
        if row == 0 do
          colors.dim <> String.pad_trailing("Select a project", width) <> colors.reset
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
    colors = Utils.colors()

    colors.bold <>
      colors.green <> String.pad_trailing("Editing ##{ticket.id}", width) <> colors.reset
  end

  defp build_edit_row(1, _state, _ticket, width), do: String.duplicate(" ", width)

  defp build_edit_row(row, state, ticket, width) do
    colors = Utils.colors()
    fields = State.editable_fields()
    total_field_rows = length(fields) * 2 + 2

    cond do
      row <= total_field_rows ->
        render_field_row(row, state, ticket, fields, width)

      row == total_field_rows + 1 ->
        colors.dim <>
          String.pad_trailing("Tab/Shift+Tab:nav  Enter:save  Esc:cancel", width) <>
          colors.reset

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
    colors = Utils.colors()
    label = Utils.field_label(field)

    if is_active do
      colors.green <> colors.bold <> String.pad_trailing(label, width) <> colors.reset
    else
      colors.dim <> String.pad_trailing(label, width) <> colors.reset
    end
  end

  @value_indent "  "

  defp build_field_input_line(state, ticket, field, width, is_active) do
    indent_len = String.length(@value_indent)

    value =
      if is_active do
        state.edit_buffer || ""
      else
        Utils.get_display_value(ticket, field)
      end

    if is_active do
      build_input_field_line(value, state.edit_cursor, width, indent_len)
    else
      @value_indent <>
        String.pad_trailing(String.slice(value, 0, width - indent_len), width - indent_len)
    end
  end

  defp build_input_field_line(value, cursor, width, indent_len) do
    colors = Utils.colors()
    cursor = min(cursor, String.length(value))
    {before, after_cursor} = String.split_at(value, cursor)

    max_visible = width - indent_len
    visible_before = String.slice(before, -max(0, max_visible - 1), max_visible - 1)
    cursor_char = if after_cursor == "", do: " ", else: String.first(after_cursor)

    after_char =
      if String.length(after_cursor) > 1, do: String.slice(after_cursor, 1..-1//1), else: ""

    remaining = max_visible - String.length(visible_before) - 1
    visible_after = String.slice(after_char, 0, max(0, remaining))

    content =
      @value_indent <>
        visible_before <>
        colors.reverse <> cursor_char <> colors.reset <> visible_after

    used = indent_len + String.length(visible_before) + 1 + String.length(visible_after)
    padding = max(0, width - used)

    content <> String.duplicate(" ", padding)
  end

  defp build_view_content_line(row, state, width, _height) do
    colors = Utils.colors()
    ticket = State.current_ticket(state)

    if ticket == nil do
      if row == 0 do
        colors.dim <> String.pad_trailing("No ticket selected", width) <> colors.reset
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
    colors = Utils.colors()
    file = State.current_research_file(state)

    if file == nil do
      if row == 0 do
        colors.dim <> String.pad_trailing("No file selected", width) <> colors.reset
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
        Utils.wrap_text(text, width) |> Enum.map(&{:md_h1, &1})

      String.starts_with?(line, "## ") ->
        text = String.trim_leading(line, "## ")
        Utils.wrap_text(text, width) |> Enum.map(&{:md_h2, &1})

      String.starts_with?(line, "### ") ->
        text = String.trim_leading(line, "### ")
        Utils.wrap_text(text, width) |> Enum.map(&{:md_h3, &1})

      String.starts_with?(line, "- ") or String.starts_with?(line, "* ") ->
        Utils.wrap_text(line, width) |> Enum.map(&{:md_list, &1})

      String.starts_with?(line, "```") ->
        [{:md_code_fence, String.slice(line, 0, width)}]

      line == "" ->
        [{:blank}]

      true ->
        Utils.wrap_text(line, width) |> Enum.map(&{:text, &1})
    end
  end

  defp parse_file_line(line, :json, width) do
    Utils.wrap_text(line, width) |> Enum.map(&{:json_line, &1})
  end

  defp parse_file_line(line, _type, width) do
    Utils.wrap_text(line, width) |> Enum.map(&{:text, &1})
  end

  defp render_file_line_to_string({:header, text}, width) do
    colors = Utils.colors()
    content_width = width - 1
    " " <> colors.bold <> colors.green <> Utils.pad_content(text, content_width) <> colors.reset
  end

  defp render_file_line_to_string({:blank}, width) do
    String.duplicate(" ", width)
  end

  defp render_file_line_to_string({:md_h1, text}, width) do
    colors = Utils.colors()
    content_width = width - 1
    " " <> colors.bold <> colors.green <> Utils.pad_content(text, content_width) <> colors.reset
  end

  defp render_file_line_to_string({:md_h2, text}, width) do
    colors = Utils.colors()
    content_width = width - 1
    " " <> colors.bold <> colors.yellow <> Utils.pad_content(text, content_width) <> colors.reset
  end

  defp render_file_line_to_string({:md_h3, text}, width) do
    colors = Utils.colors()
    content_width = width - 1
    " " <> colors.bold <> Utils.pad_content(text, content_width) <> colors.reset
  end

  defp render_file_line_to_string({:md_list, text}, width) do
    colors = Utils.colors()
    content_width = width - 1
    " " <> colors.green <> Utils.pad_content(text, content_width) <> colors.reset
  end

  defp render_file_line_to_string({:md_code_fence, text}, width) do
    colors = Utils.colors()
    content_width = width - 1
    " " <> colors.dim <> Utils.pad_content(text, content_width) <> colors.reset
  end

  defp render_file_line_to_string({:json_line, text}, width) do
    colors = Utils.colors()
    content_width = width - 1
    " " <> colors.dim <> Utils.pad_content(text, content_width) <> colors.reset
  end

  defp render_file_line_to_string({:text, text}, width) do
    content_width = width - 1
    " " <> Utils.pad_content(text, content_width)
  end

  defp render_file_line_to_string({:error, text}, width) do
    colors = Utils.colors()
    content_width = width - 1
    " " <> colors.red <> Utils.pad_content(text, content_width) <> colors.reset
  end

  defp render_detail_line_to_string({:header, text}, width) do
    colors = Utils.colors()
    content_width = width - 1
    " " <> colors.bold <> colors.green <> Utils.pad_content(text, content_width) <> colors.reset
  end

  defp render_detail_line_to_string({:blank}, width) do
    String.duplicate(" ", width)
  end

  defp render_detail_line_to_string({:section, title}, width) do
    colors = Utils.colors()
    content_width = width - 1
    " " <> colors.green <> colors.bold <> Utils.pad_content(title, content_width) <> colors.reset
  end

  defp render_detail_line_to_string({:subsection, title}, width) do
    colors = Utils.colors()
    content_width = width - 3
    "   " <> colors.dim <> Utils.pad_content(title, content_width) <> colors.reset
  end

  defp render_detail_line_to_string({:field, label, value, color}, width) do
    colors = Utils.colors()
    padded_label = String.pad_trailing(label <> ":", 12)
    value_width = max(0, width - 13)
    sliced_value = String.slice(value, 0, value_width)

    " " <>
      colors.dim <>
      padded_label <>
      colors.reset <> color <> String.pad_trailing(sliced_value, value_width) <> colors.reset
  end

  defp render_detail_line_to_string({:text, text}, width) do
    content_width = width - 1
    " " <> Utils.pad_content(text, content_width)
  end

  defp render_detail_line_to_string({:file, path, color}, width) do
    colors = Utils.colors()
    path_width = max(0, width - 5)
    "     " <> color <> Utils.pad_content(path, path_width) <> colors.reset
  end

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
    title = ticket.title || "(untitled)"
    lines ++ [{:header, "##{ticket.id}: #{title}"}, {:blank}]
  end

  defp add_metadata_lines(lines, ticket) do
    lines
    |> then(
      &(&1 ++ [{:field, "Status", to_string(ticket.status), Utils.status_color(ticket.status)}])
    )
    |> then(&(&1 ++ [{:field, "Type", to_string(ticket.type), ""}]))
    |> then(
      &(&1 ++
          [
            {:field, "Priority", to_string(ticket.priority),
             Utils.priority_color(ticket.priority)}
          ])
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
    colors = Utils.colors()
    lines ++ [{:field, "Labels", Enum.join(ticket.labels, ", "), colors.magenta}]
  end

  defp add_description_lines(lines, %{description: nil}, _width), do: lines
  defp add_description_lines(lines, %{description: ""}, _width), do: lines

  defp add_description_lines(lines, ticket, width) do
    wrapped = Utils.wrap_text(ticket.description, width - 2)
    text_lines = Enum.map(wrapped, &{:text, &1})
    lines ++ [{:blank}, {:section, "Description"}] ++ text_lines
  end

  defp add_acceptance_criteria_lines(lines, %{acceptance_criteria: []}, _width), do: lines

  defp add_acceptance_criteria_lines(lines, ticket, width) do
    criteria_lines =
      ticket.acceptance_criteria
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {criterion, idx} ->
        wrapped = Utils.wrap_text("#{idx}. #{criterion}", width - 2)
        Enum.map(wrapped, &{:text, &1})
      end)

    lines ++ [{:blank}, {:section, "Acceptance Criteria"}] ++ criteria_lines
  end

  defp add_implementation_notes_lines(lines, %{implementation_notes: nil}, _width), do: lines
  defp add_implementation_notes_lines(lines, %{implementation_notes: ""}, _width), do: lines

  defp add_implementation_notes_lines(lines, ticket, width) do
    wrapped = Utils.wrap_text(ticket.implementation_notes, width - 2)
    text_lines = Enum.map(wrapped, &{:text, &1})
    lines ++ [{:blank}, {:section, "Implementation Notes"}] ++ text_lines
  end

  defp add_files_lines(lines, ticket) do
    colors = Utils.colors()
    has_create = ticket.files.create != []
    has_modify = ticket.files.modify != []

    if has_create or has_modify do
      lines
      |> then(&(&1 ++ [{:blank}, {:section, "Files"}]))
      |> maybe_add_create_files(ticket.files.create, colors)
      |> maybe_add_modify_files(ticket.files.modify, colors)
    else
      lines
    end
  end

  defp maybe_add_create_files(lines, [], _colors), do: lines

  defp maybe_add_create_files(lines, files, colors) do
    file_lines = Enum.map(files, &{:file, &1, colors.green})
    lines ++ [{:subsection, "Create:"}] ++ file_lines
  end

  defp maybe_add_modify_files(lines, [], _colors), do: lines

  defp maybe_add_modify_files(lines, files, colors) do
    file_lines = Enum.map(files, &{:file, &1, colors.yellow})
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
    colors = Utils.colors()
    blocked = Enum.join(blocked_by, ", ")
    lines ++ [{:field, "Blocked by", blocked, colors.red}]
  end

  defp maybe_add_blocks(lines, []), do: lines

  defp maybe_add_blocks(lines, blocks_list) do
    colors = Utils.colors()
    blocks = Enum.join(blocks_list, ", ")
    lines ++ [{:field, "Blocks", blocks, colors.yellow}]
  end
end
