defmodule Albedo.Session.Supervisor do
  @moduledoc """
  DynamicSupervisor for session workers.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new session worker.
  """
  def start_session(codebase_path, task, opts \\ []) do
    spec = {Albedo.Session.Worker, {codebase_path, task, opts}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Start a new greenfield planning session.
  """
  def start_greenfield_session(project_name, task, opts \\ []) do
    spec = {Albedo.Session.Worker, {:greenfield, project_name, task, opts}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Resume an existing session.
  """
  def resume_session(session_dir) do
    spec = {Albedo.Session.Worker, {:resume, session_dir}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stop a session worker.
  """
  def stop_session(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  List all active session workers.
  """
  def list_sessions do
    DynamicSupervisor.which_children(__MODULE__)
  end
end
