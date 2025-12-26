defmodule Albedo.Project.Supervisor do
  @moduledoc """
  DynamicSupervisor for project workers.
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
  Start a new project worker.
  """
  def start_project(codebase_path, task, opts \\ []) do
    spec = {Albedo.Project.Worker, {codebase_path, task, opts}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Start a new greenfield planning project.
  """
  def start_greenfield_project(project_name, task, opts \\ []) do
    spec = {Albedo.Project.Worker, {:greenfield, project_name, task, opts}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Resume an existing project.
  """
  def resume_project(project_dir) do
    spec = {Albedo.Project.Worker, {:resume, project_dir}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stop a project worker.
  """
  def stop_project(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  List all active project workers.
  """
  def list_projects do
    DynamicSupervisor.which_children(__MODULE__)
  end
end
