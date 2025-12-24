defmodule Albedo do
  @moduledoc """
  Albedo - Codebase-to-Tickets CLI Tool.

  Given an unfamiliar codebase and a task description, Albedo systematically
  investigates both the domain and the code, then produces a comprehensive,
  actionable work breakdown with tickets.

  The name comes from alchemy - Albedo (whitening) represents purification
  and clarity, transforming confusion into understanding.

  ## Usage

      # Initialize configuration
      albedo init

      # Analyze a codebase
      albedo analyze /path/to/codebase --task "Add user authentication"

      # Resume an incomplete session
      albedo resume ~/.albedo/sessions/2025-01-15_user-auth/

      # List sessions
      albedo sessions

      # Show session output
      albedo show 2025-01-15_user-auth

  ## Configuration

  Configuration is stored at `~/.albedo/config.toml`.
  See `Albedo.Config` for details.
  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the version of Albedo.
  """
  def version, do: @version

  @doc """
  Check if Albedo is properly configured.
  """
  def configured? do
    config = Albedo.Config.load!()
    api_key = Albedo.Config.api_key(config)
    api_key != nil && api_key != ""
  end

  @doc """
  Start an analysis session.

  See `Albedo.Session.start/3` for options.
  """
  defdelegate analyze(path, task, opts \\ []), to: Albedo.Session, as: :start

  @doc """
  Resume an existing session.

  See `Albedo.Session.resume/1` for details.
  """
  defdelegate resume(session_dir), to: Albedo.Session
end
