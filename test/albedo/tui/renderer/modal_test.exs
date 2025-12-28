defmodule Albedo.TUI.Renderer.ModalTest do
  use ExUnit.Case, async: true

  alias Albedo.TUI.Renderer.Modal

  defp build_modal_state(modal_type, phase \\ :input) do
    %{
      modal: modal_type,
      modal_scroll: 0,
      modal_data: %{
        phase: phase,
        name: "test-project",
        name_buffer: "test-project",
        task_buffer: "Build a feature",
        title_buffer: "",
        cursor: 0,
        active_field: :name,
        logs: [],
        total_agents: 0,
        current_agent: 0,
        agent_name: nil
      }
    }
  end

  defp extract_content(result) do
    result
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n", fn {_start_col, content} -> content end)
  end

  describe "build_modal_overlay/3" do
    test "returns list of lines" do
      state = build_modal_state(:plan)
      result = Modal.build_modal_overlay(state, 120, 40)

      assert is_list(result)
      assert length(result) == 40
    end

    test "includes nil for rows outside modal" do
      state = build_modal_state(:plan)
      result = Modal.build_modal_overlay(state, 120, 40)

      assert Enum.any?(result, &is_nil/1)
    end

    test "includes modal content tuples for rows inside modal" do
      state = build_modal_state(:plan)
      result = Modal.build_modal_overlay(state, 120, 40)

      content_lines = Enum.reject(result, &is_nil/1)
      refute Enum.empty?(content_lines)

      assert Enum.all?(content_lines, fn {start_col, content} ->
               is_integer(start_col) and is_binary(content)
             end)
    end

    test "shows Plan title for plan modal" do
      state = build_modal_state(:plan)
      result = Modal.build_modal_overlay(state, 120, 40)

      content = extract_content(result)
      assert String.contains?(content, "Plan")
    end

    test "shows Analyze title for analyze modal" do
      state = build_modal_state(:analyze)
      result = Modal.build_modal_overlay(state, 120, 40)

      content = extract_content(result)
      assert String.contains?(content, "Analyze")
    end

    test "shows input hints for input phase" do
      state = build_modal_state(:plan, :input)
      result = Modal.build_modal_overlay(state, 120, 40)

      content = extract_content(result)
      assert String.contains?(content, "Tab") or String.contains?(content, "Enter")
    end

    test "shows running status for running phase" do
      state = build_modal_state(:plan, :running)
      result = Modal.build_modal_overlay(state, 120, 40)

      content = extract_content(result)
      assert String.contains?(content, "Running")
    end

    test "shows close hint for completed phase" do
      state = build_modal_state(:plan, :completed)
      result = Modal.build_modal_overlay(state, 120, 40)

      content = extract_content(result)
      assert String.contains?(content, "close") or String.contains?(content, "Esc")
    end

    test "handles small dimensions" do
      state = build_modal_state(:plan)
      result = Modal.build_modal_overlay(state, 60, 20)

      assert is_list(result)
      assert length(result) == 20
    end

    test "includes project name in title after input phase" do
      state = build_modal_state(:plan, :running)
      result = Modal.build_modal_overlay(state, 120, 40)

      content = extract_content(result)
      assert String.contains?(content, "test-project")
    end
  end
end
