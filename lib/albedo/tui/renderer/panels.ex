defmodule Albedo.TUI.Renderer.Panels do
  @moduledoc """
  Renders the left panel sections: Projects, Tickets, and Research.
  """

  alias Albedo.TUI.Renderer.Utils

  def build_left_panel_char(panel_row, state, width, section_height, panel_height) do
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
    colors = Utils.colors()
    is_active = state.active_panel == :projects
    border_chars = Utils.border_chars(is_active)
    border_color = if is_active, do: colors.kanagawa_orange, else: colors.white

    cond do
      row == 1 ->
        Utils.build_top_border(" [1] Projects ", width, border_color, is_active)

      row == height ->
        Utils.build_bottom_border(width, border_color, is_active)

      true ->
        content_row = row - 2
        content = build_project_content(content_row, state, width - 2)

        border_color <>
          border_chars.vertical <>
          colors.reset <> content <> border_color <> border_chars.vertical <> colors.reset
    end
  end

  defp build_project_content(row, state, width) do
    project = Enum.at(state.projects, row)

    if project do
      is_selected = row == state.current_project
      is_active = state.active_panel == :projects
      build_project_item(project, width, is_selected, is_active)
    else
      String.duplicate(" ", width)
    end
  end

  defp build_project_item(project, width, is_selected, _is_active) do
    colors = Utils.colors()
    bg = if is_selected, do: colors.bg_kanagawa_sky_blue <> colors.black, else: ""
    state_indicator = Utils.project_state_indicator(project.state)
    id = String.slice(project.id, 0, width - 4)

    bg <> " " <> state_indicator <> " " <> String.pad_trailing(id, width - 3) <> colors.reset
  end

  defp build_tickets_line(row, state, width, height) do
    colors = Utils.colors()
    is_active = state.active_panel == :tickets
    border_chars = Utils.border_chars(is_active)
    border_color = if is_active, do: colors.kanagawa_orange, else: colors.white

    cond do
      row == 1 ->
        Utils.build_top_border(" [2] Tickets ", width, border_color, is_active)

      row == height ->
        Utils.build_bottom_border(width, border_color, is_active)

      true ->
        content_row = row - 2
        content = build_ticket_content(content_row, state, width - 2)

        border_color <>
          border_chars.vertical <>
          colors.reset <> content <> border_color <> border_chars.vertical <> colors.reset
    end
  end

  defp build_ticket_content(row, state, width) do
    colors = Utils.colors()

    if state.data do
      ticket = Enum.at(state.data.tickets, row)

      if ticket do
        is_selected = row == state.selected_ticket
        is_active = state.active_panel == :tickets
        is_viewing = state.detail_content == :ticket
        build_ticket_item(ticket, width, is_selected, is_active, is_viewing)
      else
        String.duplicate(" ", width)
      end
    else
      if row == 0 do
        msg = "No project selected"
        colors.dim <> String.pad_trailing(msg, width) <> colors.reset
      else
        String.duplicate(" ", width)
      end
    end
  end

  defp build_ticket_item(ticket, width, is_selected, is_active, is_viewing) do
    colors = Utils.colors()
    show_highlight = is_selected and (is_active or is_viewing)
    bg = if show_highlight, do: colors.bg_kanagawa_sky_blue <> colors.black, else: ""
    status_ind = Utils.status_indicator(ticket.status)

    points = if ticket.estimate, do: " [#{ticket.estimate}]", else: ""
    points_len = String.length(points)
    prefix_len = 3
    title_width = max(0, width - prefix_len - points_len)
    title = String.pad_trailing(String.slice(ticket.title, 0, title_width), title_width)

    bg <> " " <> status_ind <> " " <> title <> points <> colors.reset
  end

  defp build_research_line(row, state, width, height) do
    colors = Utils.colors()
    is_active = state.active_panel == :research
    border_chars = Utils.border_chars(is_active)
    border_color = if is_active, do: colors.kanagawa_orange, else: colors.white

    cond do
      row == 1 ->
        Utils.build_top_border(" [3] Research ", width, border_color, is_active)

      row == height ->
        Utils.build_bottom_border(width, border_color, is_active)

      true ->
        content_row = row - 2
        content = build_research_content(content_row, state, width - 2)

        border_color <>
          border_chars.vertical <>
          colors.reset <> content <> border_color <> border_chars.vertical <> colors.reset
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
        is_selected = row == state.selected_file
        is_active = state.active_panel == :research
        is_viewing = state.detail_content == :research
        build_research_item(file, width, is_selected, is_active, is_viewing)
    end
  end

  defp build_empty_research_message(0, state, width) do
    colors = Utils.colors()
    msg = if state.data, do: "No research files", else: "Select a project"
    colors.dim <> String.pad_trailing(msg, width) <> colors.reset
  end

  defp build_empty_research_message(_row, _state, width) do
    String.duplicate(" ", width)
  end

  defp build_research_item(file, width, is_selected, is_active, is_viewing) do
    colors = Utils.colors()
    show_highlight = is_selected and (is_active or is_viewing)
    bg = if show_highlight, do: colors.bg_kanagawa_sky_blue <> colors.black, else: ""
    type_indicator = if file.type == :markdown, do: "md", else: "js"
    name = String.slice(file.name, 0, width - 5)

    bg <> " " <> type_indicator <> " " <> String.pad_trailing(name, width - 4) <> colors.reset
  end
end
