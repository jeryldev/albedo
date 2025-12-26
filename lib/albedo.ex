defmodule Albedo do
  @moduledoc """
  Albedo - Ideas-to-Tickets CLI Tool.

  Turn feature ideas into actionable implementation plans. Albedo works with
  both existing codebases and new (greenfield) projects.

  **For existing codebases:** Analyzes structure, conventions, and patterns
  to generate implementation tickets with file-level guidance.

  **For new projects:** Researches the domain, recommends tech stack and
  architecture, and generates setup and implementation tickets.

  The name comes from alchemy - Albedo (whitening) represents purification
  and clarity, transforming confusion into understanding.

  ## Usage

      # First-time setup
      ./install.sh

      # Analyze an existing codebase
      albedo analyze /path/to/codebase --task "Add user authentication"

      # Plan a new project from scratch
      albedo plan --name my_app --task "Build a todo app" --stack phoenix

      # Resume an incomplete project
      albedo resume ~/.albedo/projects/2025-01-15_user-auth/

      # List projects
      albedo projects

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
  Start an analysis project.

  See `Albedo.Project.start/3` for options.
  """
  defdelegate analyze(path, task, opts \\ []), to: Albedo.Project, as: :start

  @doc """
  Resume an existing project.

  See `Albedo.Project.resume/1` for details.
  """
  defdelegate resume(project_dir), to: Albedo.Project
end
