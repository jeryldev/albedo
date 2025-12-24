defmodule Albedo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Albedo.Session.Registry,
      Albedo.Session.Supervisor,
      Albedo.Agents.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Albedo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
