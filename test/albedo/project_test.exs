defmodule Albedo.ProjectTest do
  use ExUnit.Case, async: false

  alias Albedo.Project
  alias Albedo.Project.State

  describe "replan/2" do
    test "returns error for non-existent project" do
      nonexistent = "/tmp/nonexistent_project_#{System.unique_integer([:positive])}"

      assert {:error, _reason} = Project.replan(nonexistent)
    end
  end

  describe "get_state/1" do
    test "returns error for non-existent project" do
      result = Project.get_state("nonexistent-project-id")

      assert {:error, :not_found} = result
    end
  end

  describe "answer_question/2" do
    test "returns error for non-existent project" do
      result = Project.answer_question("nonexistent-project-id", "test answer")

      assert {:error, :not_found} = result
    end
  end

  describe "reset_planning_phase logic" do
    test "resets phases for minimal scope" do
      state = create_test_state()
      reset_state = reset_planning_phase(state, scope: "minimal")

      assert reset_state.phases[:change_planning].status == :pending
      assert reset_state.phases[:impact_analysis].status == :completed
      assert reset_state.state == :created
    end

    test "resets phases for full scope" do
      state = create_test_state()
      reset_state = reset_planning_phase(state, scope: "full")

      assert reset_state.phases[:change_planning].status == :pending
      assert reset_state.phases[:impact_analysis].status == :pending
      assert reset_state.state == :created
    end

    test "defaults to full scope when not specified" do
      state = create_test_state()
      reset_state = reset_planning_phase(state, [])

      assert reset_state.phases[:change_planning].status == :pending
      assert reset_state.phases[:impact_analysis].status == :pending
    end
  end

  defp create_test_state do
    state = State.new("/tmp/codebase", "Test task")

    phases =
      Enum.reduce(State.phases(), state.phases, fn phase, acc ->
        Map.update!(acc, phase, fn ps ->
          %{
            ps
            | status: :completed,
              started_at: DateTime.utc_now(),
              completed_at: DateTime.utc_now()
          }
        end)
      end)

    %{state | phases: phases, state: :completed}
  end

  defp reset_planning_phase(state, opts) do
    scope = opts[:scope] || "full"

    phases_to_reset =
      case scope do
        "minimal" -> [:change_planning]
        _ -> [:impact_analysis, :change_planning]
      end

    phases =
      Enum.reduce(phases_to_reset, state.phases, fn phase, acc ->
        Map.update!(acc, phase, fn ps ->
          %{ps | status: :pending, started_at: nil, completed_at: nil, duration_ms: nil}
        end)
      end)

    %{state | phases: phases, state: :created}
  end
end
