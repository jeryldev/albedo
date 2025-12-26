defmodule Albedo.Project.Registry do
  @moduledoc """
  Registry for tracking projects by ID.
  Enables message routing to project workers.
  """

  @doc """
  Start the registry.
  """
  def start_link(_opts) do
    Registry.start_link(keys: :unique, name: __MODULE__)
  end

  @doc """
  Register a project with the given ID.
  """
  def register(project_id) do
    Registry.register(__MODULE__, project_id, nil)
  end

  @doc """
  Look up a project by ID.
  """
  def lookup(project_id) do
    case Registry.lookup(__MODULE__, project_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Get the project ID for a pid.
  """
  def get_project_id(pid) do
    case Registry.keys(__MODULE__, pid) do
      [project_id | _] -> {:ok, project_id}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Send a message to a project by ID.
  """
  def send_message(project_id, message) do
    case lookup(project_id) do
      {:ok, pid} ->
        Kernel.send(pid, message)
        :ok

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Call a project by ID.
  """
  def call(project_id, message, timeout \\ 5000) do
    case lookup(project_id) do
      {:ok, pid} ->
        GenServer.call(pid, message, timeout)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Notify project of agent completion.
  """
  def notify_agent_complete(project_id, phase, findings) do
    send_message(project_id, {:agent_complete, phase, findings})
  end

  @doc """
  Notify project of agent failure.
  """
  def notify_agent_failed(project_id, phase, reason) do
    send_message(project_id, {:agent_failed, phase, reason})
  end

  @doc """
  Child spec for supervision tree.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end
end
