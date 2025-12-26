defmodule Albedo.Project.WorkerTest do
  use ExUnit.Case, async: true

  alias Albedo.Project.State
  alias Albedo.TestSupport.Mocks

  describe "state management" do
    test "new project starts in created state" do
      state = State.new("/tmp/test", "Test task", [])
      assert state.state == :created
    end

    test "project has unique id" do
      state1 = State.new("/tmp/test", "Task 1", [])
      state2 = State.new("/tmp/test", "Task 2", [])
      refute state1.id == state2.id
    end

    test "project tracks codebase path" do
      state = State.new("/my/codebase", "Test task", [])
      assert state.codebase_path == "/my/codebase"
    end

    test "project tracks task" do
      state = State.new("/tmp/test", "My feature task", [])
      assert state.task == "My feature task"
    end
  end

  describe "phase tracking" do
    test "first_incomplete_phase returns first pending phase" do
      state = State.new("/tmp/test", "Test task", [])
      assert State.first_incomplete_phase(state) == :domain_research
    end

    test "phase completion updates state" do
      state =
        State.new("/tmp/test", "Test task", [])
        |> State.start_phase(:domain_research)
        |> State.complete_phase(:domain_research, %{content: "test"})

      assert state.phases[:domain_research].status == :completed
    end

    test "phase failure updates state" do
      state =
        State.new("/tmp/test", "Test task", [])
        |> State.start_phase(:domain_research)
        |> State.fail_phase(:domain_research, :test_error)

      assert state.phases[:domain_research].status == :failed
    end
  end

  describe "context accumulation" do
    test "phase completion adds findings to context" do
      findings = %{domain: :accounting, keywords: ["ledger"]}

      state =
        State.new("/tmp/test", "Test task", [])
        |> State.start_phase(:domain_research)
        |> State.complete_phase(:domain_research, findings)

      assert state.context[:domain_research] == findings
    end
  end

  describe "state transitions" do
    test "transition to completed" do
      state =
        State.new("/tmp/test", "Test task", [])
        |> State.transition(:completed)

      assert state.state == :completed
    end

    test "transition to failed" do
      state =
        State.new("/tmp/test", "Test task", [])
        |> State.transition(:failed)

      assert state.state == :failed
    end

    test "transition to paused" do
      state =
        State.new("/tmp/test", "Test task", [])
        |> State.transition(:paused)

      assert state.state == :paused
    end
  end

  describe "project persistence" do
    setup do
      dir = Mocks.create_temp_dir()
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "save and load project state", %{dir: dir} do
      state = State.new("/tmp/codebase", "Test task", [])
      state = %{state | project_dir: dir}

      :ok = State.save(state)

      {:ok, loaded} = State.load(dir)
      assert loaded.task == state.task
      assert loaded.codebase_path == state.codebase_path
    end
  end

  describe "phase output files" do
    test "phase_output_file returns correct filename" do
      assert State.phase_output_file(:domain_research) == "00_domain_research.md"
      assert State.phase_output_file(:tech_stack) == "01_tech_stack.md"
      assert State.phase_output_file(:architecture) == "02_architecture.md"
      assert State.phase_output_file(:conventions) == "03_conventions.md"
      assert State.phase_output_file(:feature_location) == "04_feature_location.md"
      assert State.phase_output_file(:impact_analysis) == "05_impact_analysis.md"
      assert State.phase_output_file(:change_planning) == "FEATURE.md"
    end
  end

  describe "project completion" do
    test "complete? returns false when phases pending" do
      state = State.new("/tmp/test", "Test task", [])
      refute State.complete?(state)
    end
  end
end
