defmodule Albedo.Session.Registry do
  @moduledoc """
  Registry for tracking sessions by ID.
  Enables message routing to session workers.
  """

  @doc """
  Start the registry.
  """
  def start_link(_opts) do
    Registry.start_link(keys: :unique, name: __MODULE__)
  end

  @doc """
  Register a session with the given ID.
  """
  def register(session_id) do
    Registry.register(__MODULE__, session_id, nil)
  end

  @doc """
  Look up a session by ID.
  """
  def lookup(session_id) do
    case Registry.lookup(__MODULE__, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Get the session ID for a pid.
  """
  def get_session_id(pid) do
    case Registry.keys(__MODULE__, pid) do
      [session_id | _] -> {:ok, session_id}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Send a message to a session by ID.
  """
  def send_message(session_id, message) do
    case lookup(session_id) do
      {:ok, pid} ->
        Kernel.send(pid, message)
        :ok

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Call a session by ID.
  """
  def call(session_id, message, timeout \\ 5000) do
    case lookup(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, message, timeout)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Notify session of agent completion.
  """
  def notify_agent_complete(session_id, phase, findings) do
    send_message(session_id, {:agent_complete, phase, findings})
  end

  @doc """
  Notify session of agent failure.
  """
  def notify_agent_failed(session_id, phase, reason) do
    send_message(session_id, {:agent_failed, phase, reason})
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
