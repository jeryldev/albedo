defmodule Albedo.Agents.Supervisor do
  @moduledoc """
  DynamicSupervisor for spawning agents per investigation phase.
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
  Start an agent of the given type.
  """
  def start_agent(agent_module, opts) when is_atom(agent_module) do
    spec = {agent_module, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stop an agent.
  """
  def stop_agent(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  List all active agents.
  """
  def list_agents do
    DynamicSupervisor.which_children(__MODULE__)
  end

  @doc """
  Count active agents.
  """
  def count_agents do
    DynamicSupervisor.count_children(__MODULE__)
  end
end
