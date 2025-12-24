defmodule Albedo.Session.StateTest do
  use ExUnit.Case, async: true

  alias Albedo.Session.State

  describe "new/3" do
    test "creates a new session state" do
      state = State.new("/path/to/codebase", "Add user auth")

      assert state.codebase_path == "/path/to/codebase"
      assert state.task == "Add user auth"
      assert state.state == :created
      assert is_binary(state.id)
      assert String.contains?(state.id, "add-user-auth")
    end

    test "initializes all phases as pending" do
      state = State.new("/path", "Task")

      Enum.each(State.phases(), fn phase ->
        assert state.phases[phase].status == :pending
      end)
    end

    test "generates unique session IDs" do
      state1 = State.new("/path", "Task one")
      state2 = State.new("/path", "Task two")

      refute state1.id == state2.id
    end
  end

  describe "phases/0" do
    test "returns all phases in order" do
      phases = State.phases()

      assert phases == [
               :domain_research,
               :tech_stack,
               :architecture,
               :conventions,
               :feature_location,
               :impact_analysis,
               :change_planning
             ]
    end
  end

  describe "phase_output_file/1" do
    test "returns correct output file for each phase" do
      assert State.phase_output_file(:domain_research) == "00_domain_research.md"
      assert State.phase_output_file(:tech_stack) == "01_tech_stack.md"
      assert State.phase_output_file(:change_planning) == "FEATURE.md"
    end
  end

  describe "next_phase/1" do
    test "returns next phase" do
      assert State.next_phase(:domain_research) == :tech_stack
      assert State.next_phase(:tech_stack) == :architecture
    end

    test "returns nil for last phase" do
      assert State.next_phase(:change_planning) == nil
    end
  end

  describe "first_incomplete_phase/1" do
    test "returns first pending phase" do
      state = State.new("/path", "Task")
      assert State.first_incomplete_phase(state) == :domain_research
    end

    test "returns nil when all phases complete" do
      state = State.new("/path", "Task")

      completed_phases =
        State.phases()
        |> Enum.reduce(state.phases, fn phase, acc ->
          Map.update!(acc, phase, &Map.put(&1, :status, :completed))
        end)

      state = %{state | phases: completed_phases}
      assert State.first_incomplete_phase(state) == nil
    end
  end

  describe "start_phase/2" do
    test "marks phase as in_progress" do
      state = State.new("/path", "Task")
      state = State.start_phase(state, :domain_research)

      assert state.phases[:domain_research].status == :in_progress
      assert state.phases[:domain_research].started_at != nil
      assert state.state == :researching_domain
    end
  end

  describe "complete_phase/3" do
    test "marks phase as completed with findings" do
      state = State.new("/path", "Task")
      state = State.start_phase(state, :domain_research)
      state = State.complete_phase(state, :domain_research, %{content: "findings"})

      assert state.phases[:domain_research].status == :completed
      assert state.phases[:domain_research].completed_at != nil
      assert state.phases[:domain_research].duration_ms != nil
      assert state.context[:domain_research] == %{content: "findings"}
    end

    test "transitions to next phase state" do
      state = State.new("/path", "Task")
      state = State.start_phase(state, :domain_research)
      state = State.complete_phase(state, :domain_research)

      assert state.state == :analyzing_tech_stack
    end

    test "transitions to completed when last phase finishes" do
      state = State.new("/path", "Task")

      state =
        State.phases()
        |> Enum.reduce(state, fn phase, acc ->
          acc
          |> State.start_phase(phase)
          |> State.complete_phase(phase)
        end)

      assert state.state == :completed
    end
  end

  describe "fail_phase/3" do
    test "marks phase as failed with error" do
      state = State.new("/path", "Task")
      state = State.start_phase(state, :domain_research)
      state = State.fail_phase(state, :domain_research, :timeout)

      assert state.phases[:domain_research].status == :failed
      assert state.phases[:domain_research].error == :timeout
      assert state.state == :failed
    end
  end

  describe "pause/2" do
    test "pauses session and adds question" do
      state = State.new("/path", "Task")
      state = State.pause(state, "Which database?")

      assert state.state == :paused
      assert length(state.clarifying_questions) == 1
      assert hd(state.clarifying_questions).question == "Which database?"
    end
  end

  describe "answer_question/3" do
    test "records answer and resumes session" do
      state = State.new("/path", "Task")
      state = State.pause(state, "Which database?")
      state = State.answer_question(state, "PostgreSQL", :researching_domain)

      assert state.state == :researching_domain
      assert hd(state.clarifying_questions).answer == "PostgreSQL"
    end
  end

  describe "complete?/1" do
    test "returns true when session is completed" do
      state = %{State.new("/path", "Task") | state: :completed}
      assert State.complete?(state)
    end

    test "returns false when session is not completed" do
      state = State.new("/path", "Task")
      refute State.complete?(state)
    end
  end

  describe "failed?/1" do
    test "returns true when session has failed" do
      state = %{State.new("/path", "Task") | state: :failed}
      assert State.failed?(state)
    end

    test "returns false when session has not failed" do
      state = State.new("/path", "Task")
      refute State.failed?(state)
    end
  end
end
