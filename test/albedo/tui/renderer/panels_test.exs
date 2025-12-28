defmodule Albedo.TUI.Renderer.PanelsTest do
  use ExUnit.Case, async: true

  alias Albedo.TUI.Renderer.Panels

  defp build_state(opts \\ []) do
    %{
      active_panel: opts[:active_panel] || :projects,
      projects: opts[:projects] || [],
      current_project: opts[:current_project] || 0,
      data: opts[:data],
      selected_ticket: opts[:selected_ticket] || 0,
      selected_file: opts[:selected_file] || 0,
      research_files: opts[:research_files] || [],
      detail_content: opts[:detail_content] || :ticket,
      panel_scroll: %{projects: 0, tickets: 0, research: 0}
    }
  end

  defp sample_project(id, state \\ "completed") do
    %{id: id, state: state}
  end

  defp dims(width \\ 40, section_height \\ 10, panel_height \\ 30) do
    %{width: width, section_height: section_height, panel_height: panel_height}
  end

  describe "build_left_panel_row/3" do
    test "returns string for valid row" do
      state = build_state()
      result = Panels.build_left_panel_row(1, state, dims())

      assert is_binary(result)
    end

    test "returns spaces for out of range row" do
      state = build_state()
      result = Panels.build_left_panel_row(0, state, dims())

      assert String.trim(result) == ""
    end

    test "returns spaces for row beyond panel height" do
      state = build_state()
      result = Panels.build_left_panel_row(100, state, dims())

      assert String.trim(result) == ""
    end

    test "builds projects section for first section rows" do
      state = build_state(active_panel: :projects)
      result = Panels.build_left_panel_row(1, state, dims())

      assert String.contains?(result, "Projects")
    end

    test "builds tickets section for middle rows" do
      state = build_state(active_panel: :tickets)
      result = Panels.build_left_panel_row(11, state, dims())

      assert String.contains?(result, "Tickets")
    end

    test "shows project items in content rows" do
      projects = [sample_project("my-project")]
      state = build_state(projects: projects, current_project: 0)

      content_found =
        Enum.any?(2..9, fn row ->
          result = Panels.build_left_panel_row(row, state, dims())
          String.contains?(result, "my-project")
        end)

      assert content_found
    end

    test "shows state indicator for projects" do
      projects = [sample_project("proj", "completed")]
      state = build_state(projects: projects)

      indicator_found =
        Enum.any?(2..9, fn row ->
          result = Panels.build_left_panel_row(row, state, dims())
          String.contains?(result, "✓")
        end)

      assert indicator_found
    end

    test "uses heavy borders for active panel" do
      state = build_state(active_panel: :projects)
      result = Panels.build_left_panel_row(1, state, dims())

      assert String.contains?(result, "━") or String.contains?(result, "┏")
    end

    test "uses light borders for inactive panel" do
      state = build_state(active_panel: :tickets)
      result = Panels.build_left_panel_row(1, state, dims())

      assert String.contains?(result, "─") or String.contains?(result, "┌")
    end
  end

  describe "projects section" do
    test "shows empty space when no projects" do
      state = build_state(projects: [])
      result = Panels.build_left_panel_row(3, state, dims())

      assert is_binary(result)
    end

    test "highlights selected project" do
      projects = [sample_project("proj1"), sample_project("proj2")]
      state = build_state(projects: projects, current_project: 0, active_panel: :projects)

      project_found =
        Enum.any?(2..9, fn row ->
          result = Panels.build_left_panel_row(row, state, dims())
          String.contains?(result, "proj1")
        end)

      assert project_found
    end

    test "shows multiple projects" do
      projects = [sample_project("proj1"), sample_project("proj2")]
      state = build_state(projects: projects)

      all_content =
        Enum.map_join(2..9, "\n", fn row ->
          Panels.build_left_panel_row(row, state, dims())
        end)

      assert String.contains?(all_content, "proj1")
      assert String.contains?(all_content, "proj2")
    end
  end

  describe "section boundaries" do
    test "projects section ends at section_height" do
      state = build_state()
      section_height = 10

      border_row = Panels.build_left_panel_row(section_height, state, dims(40, section_height, 30))

      assert String.contains?(border_row, "└") or String.contains?(border_row, "┗")
    end

    test "tickets section starts after projects" do
      state = build_state()
      section_height = 10

      tickets_row =
        Panels.build_left_panel_row(section_height + 1, state, dims(40, section_height, 30))

      assert String.contains?(tickets_row, "Tickets")
    end
  end

  describe "nil title handling" do
    test "renders ticket with nil title as (untitled)" do
      ticket = %{id: "1", title: nil, status: :pending, estimate: nil}
      data = %{tickets: [ticket]}
      state = build_state(data: data, active_panel: :tickets, selected_ticket: 0)

      all_content =
        Enum.map_join(12..19, "\n", fn row ->
          Panels.build_left_panel_row(row, state, dims())
        end)

      assert String.contains?(all_content, "(untitled)")
    end
  end
end
