defmodule Albedo.TUI.Renderer.DetailTest do
  use ExUnit.Case, async: true

  alias Albedo.TUI.{Renderer.Detail, State}

  defp build_state(opts \\ []) do
    base = State.new()

    base
    |> maybe_put(:active_panel, opts[:active_panel])
    |> maybe_put(:mode, opts[:mode])
    |> maybe_put(:data, opts[:data])
    |> maybe_put(:selected_ticket, opts[:selected_ticket])
    |> maybe_put(:detail_scroll, opts[:detail_scroll])
    |> maybe_put(:detail_content, opts[:detail_content])
  end

  defp maybe_put(state, _key, nil), do: state
  defp maybe_put(state, key, value), do: Map.put(state, key, value)

  defp sample_ticket do
    %{
      id: "1",
      title: "Test Ticket",
      description: "A test description",
      type: :feature,
      status: :pending,
      priority: :medium,
      estimate: 3,
      labels: ["test"],
      acceptance_criteria: [],
      implementation_notes: nil,
      files: %{create: [], modify: []},
      dependencies: %{blocked_by: [], blocks: []}
    }
  end

  defp sample_data do
    %{
      tickets: [sample_ticket()],
      research_files: []
    }
  end

  describe "build_right_panel_char/4" do
    test "returns string for valid row" do
      state = build_state()
      result = Detail.build_right_panel_char(1, state, 60, 30)

      assert is_binary(result)
    end

    test "returns spaces for out of range row" do
      state = build_state()
      result = Detail.build_right_panel_char(0, state, 60, 30)

      assert String.trim(result) == ""
    end

    test "returns spaces for row beyond height" do
      state = build_state()
      result = Detail.build_right_panel_char(100, state, 60, 30)

      assert String.trim(result) == ""
    end

    test "builds header with Detail title for row 1" do
      state = build_state()
      result = Detail.build_right_panel_char(1, state, 60, 30)

      assert String.contains?(result, "Detail")
    end

    test "builds header with Edit title in edit mode" do
      state = build_state(mode: :edit, data: sample_data())
      result = Detail.build_right_panel_char(1, state, 60, 30)

      assert String.contains?(result, "Edit")
    end

    test "uses heavy borders for active panel" do
      state = build_state(active_panel: :detail)
      result = Detail.build_right_panel_char(1, state, 60, 30)

      assert String.contains?(result, "━") or String.contains?(result, "┏")
    end

    test "uses light borders for inactive panel" do
      state = build_state(active_panel: :projects)
      result = Detail.build_right_panel_char(1, state, 60, 30)

      assert String.contains?(result, "─") or String.contains?(result, "┌")
    end

    test "builds bottom border for last row" do
      state = build_state()
      result = Detail.build_right_panel_char(30, state, 60, 30)

      assert String.contains?(result, "└") or String.contains?(result, "┗")
    end
  end

  describe "content rendering" do
    test "shows 'Select a project' when no data" do
      state = build_state(data: nil)

      content =
        Enum.map_join(2..10, "\n", fn row ->
          Detail.build_right_panel_char(row, state, 60, 30)
        end)

      assert String.contains?(content, "Select a project")
    end

    test "shows ticket info when data is present" do
      state = build_state(data: sample_data(), selected_ticket: 0)

      content =
        Enum.map_join(2..20, "\n", fn row ->
          Detail.build_right_panel_char(row, state, 60, 30)
        end)

      assert String.contains?(content, "Test Ticket") or
               String.contains?(content, "#1") or
               String.contains?(content, "feature")
    end

    test "renders edit mode content" do
      state = build_state(mode: :edit, data: sample_data(), selected_ticket: 0)

      content =
        Enum.map_join(2..10, "\n", fn row ->
          Detail.build_right_panel_char(row, state, 60, 30)
        end)

      assert String.contains?(content, "Editing") or String.contains?(content, "#1")
    end
  end

  describe "panel dimensions" do
    test "respects width parameter" do
      state = build_state()
      result = Detail.build_right_panel_char(5, state, 80, 30)

      visible_length = String.length(String.replace(result, ~r/\e\[[0-9;]*m/, ""))
      assert visible_length <= 80
    end

    test "works with small dimensions" do
      state = build_state()
      result = Detail.build_right_panel_char(1, state, 20, 10)

      assert is_binary(result)
    end
  end
end
