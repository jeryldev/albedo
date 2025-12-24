defmodule Albedo.Session do
  @moduledoc """
  Public interface for managing analysis sessions.
  """

  alias Albedo.Session.{Registry, State, Supervisor}

  @timeout 600_000

  @doc """
  Start a new analysis session and wait for completion.
  """
  def start(codebase_path, task, opts \\ []) do
    case Supervisor.start_session(codebase_path, task, opts) do
      {:ok, pid} ->
        wait_for_completion(pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Start a new greenfield planning session (no existing codebase).
  """
  def start_greenfield(project_name, task, opts \\ []) do
    greenfield_opts = Keyword.put(opts, :greenfield, true)

    case Supervisor.start_greenfield_session(project_name, task, greenfield_opts) do
      {:ok, pid} ->
        wait_for_completion(pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resume an existing session and wait for completion.
  """
  def resume(session_dir) do
    case Supervisor.resume_session(session_dir) do
      {:ok, pid} ->
        wait_for_completion(pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Re-run the planning phase with different parameters.
  """
  def replan(session_dir, opts \\ []) do
    case State.load(session_dir) do
      {:ok, state} ->
        state = reset_planning_phase(state, opts)
        State.save(state)
        resume(session_dir)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Answer a clarifying question in a paused session.
  """
  def answer_question(session_id, answer) do
    Registry.call(session_id, {:answer_question, answer})
  end

  @doc """
  Get the current state of a session.
  """
  def get_state(session_id) do
    Registry.call(session_id, :get_state)
  end

  defp wait_for_completion(pid) do
    ref = Process.monitor(pid)

    state = GenServer.call(pid, :get_state, @timeout)
    session_dir = state.session_dir

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        case State.load(session_dir) do
          {:ok, final_state} ->
            if State.failed?(final_state) do
              {:error, {:phase_failed, final_state.id, session_dir}}
            else
              result = build_result(final_state)
              {:ok, final_state.id, result}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, reason}
    after
      @timeout ->
        Process.demonitor(ref, [:flush])
        {:error, :timeout}
    end
  catch
    :exit, {:noproc, _} ->
      {:error, :session_not_found}

    :exit, {:timeout, _} ->
      {:error, :timeout}
  end

  defp build_result(state) do
    %{
      session_id: state.id,
      output_path: Path.join(state.session_dir, "FEATURE.md"),
      tickets_count: state.summary[:tickets_count],
      total_points: state.summary[:total_points],
      files_to_create: state.summary[:files_to_create],
      files_to_modify: state.summary[:files_to_modify],
      risks_identified: state.summary[:risks_identified],
      recommended_stack: state.summary[:recommended_stack],
      setup_steps: state.summary[:setup_steps]
    }
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
