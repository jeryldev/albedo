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

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        state = GenServer.call(pid, :get_state, @timeout)
        result = GenServer.call(pid, :get_result, @timeout)
        {:ok, state.id, result}

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
