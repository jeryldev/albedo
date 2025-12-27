defmodule Albedo.CLI.Commands.Misc do
  @moduledoc """
  CLI commands for miscellaneous operations.
  Handles show, tui, and path commands.
  """

  alias Albedo.CLI.Output
  alias Albedo.{Config, TUI}

  def show(project_id) do
    Output.print_header()
    config = Config.load!()
    project_path = Path.join(Config.projects_dir(config), project_id)

    unless File.dir?(project_path) do
      Output.print_error("Project not found: #{project_id}")
      halt_with_error(1)
    end

    feature_file = Path.join(project_path, "FEATURE.md")

    if File.exists?(feature_file) do
      case File.read(feature_file) do
        {:ok, content} ->
          IO.puts(content)

        {:error, reason} ->
          Output.print_error("Failed to read FEATURE.md: #{inspect(reason)}")
      end
    else
      Output.print_info("Project #{project_id} does not have a FEATURE.md yet.")
      Output.print_info("The project may be incomplete. Try 'albedo resume #{project_path}'")
    end
  end

  def tui do
    case TUI.start() do
      :ok ->
        :ok

      {:error, :not_a_tty} ->
        Output.print_error("TUI requires a terminal (TTY)")
        IO.puts("")
        Output.print_info("Use the albedo-tui command instead:")
        IO.puts("")
        IO.puts("  albedo-tui")
        IO.puts("")
        halt_with_error(1)
    end
  end

  def path(project_id) do
    config = Config.load!()
    project_path = Path.join(Config.projects_dir(config), project_id)

    if File.dir?(project_path) do
      IO.puts(project_path)
    else
      IO.puts(:stderr, "Project not found: #{project_id}")
      halt_with_error(1)
    end
  end

  @spec halt_with_error(non_neg_integer()) :: no_return()
  defp halt_with_error(code) do
    if Application.get_env(:albedo, :test_mode, false) do
      throw({:cli_halt, code})
    else
      System.halt(code)
    end
  end
end
