defmodule Albedo.CLI do
  @moduledoc """
  Command-line interface for Albedo.
  Parses arguments and dispatches to appropriate commands.
  """

  alias Albedo.CLI.{Commands, Output}

  @cmd_help "help"
  @cmd_init "init"
  @cmd_analyze "analyze"
  @cmd_resume "resume"
  @cmd_projects "projects"
  @cmd_show "show"
  @cmd_replan "replan"
  @cmd_plan "plan"
  @cmd_config "config"
  @cmd_path "path"
  @cmd_tickets "tickets"
  @cmd_tui "tui"

  @doc """
  Main entry point for the CLI.
  """
  def main(args) do
    args
    |> parse_args()
    |> run()
  end

  @spec halt_with_error(non_neg_integer()) :: no_return()
  defp halt_with_error(code) do
    if Application.get_env(:albedo, :test_mode, false) do
      throw({:cli_halt, code})
    else
      System.halt(code)
    end
  end

  defp parse_args(args) do
    {opts, args, invalid} =
      OptionParser.parse(args,
        strict: [
          help: :boolean,
          version: :boolean,
          task: :string,
          interactive: :boolean,
          scope: :string,
          stack: :string,
          database: :string,
          name: :string,
          project: :string,
          status: :string,
          json: :boolean,
          format: :string,
          output: :string,
          all: :boolean,
          priority: :string,
          points: :integer,
          title: :string,
          description: :string,
          type: :string,
          labels: :string,
          yes: :boolean,
          verbose: :boolean
        ]
      )

    {opts, args, invalid}
  end

  defp run({_opts, _args, [_ | _] = invalid}), do: handle_invalid_args(invalid)
  defp run({opts, args, []}) when is_list(opts), do: dispatch_command(opts, args)

  defp dispatch_command(opts, args) do
    cond do
      opts[:help] -> Output.print_help()
      opts[:version] -> Output.print_version()
      true -> run_command(args, opts)
    end
  end

  defp handle_invalid_args(invalid) do
    Output.print_invalid_args(invalid)
    halt_with_error(1)
  end

  defp run_command([], _opts) do
    Output.print_help()
  end

  defp run_command([@cmd_help | _], _opts) do
    Output.print_help()
  end

  defp run_command([@cmd_init | _], _opts) do
    Commands.Analysis.init()
  end

  defp run_command([@cmd_analyze], _opts) do
    Output.print_error("Missing codebase path")

    IO.puts(
      "Usage: albedo #{@cmd_analyze} /path/to/codebase --task \"Description of what to build\""
    )

    halt_with_error(1)
  end

  defp run_command([@cmd_analyze, path | _], opts) do
    Commands.Analysis.analyze(path, opts)
  end

  defp run_command([@cmd_resume], _opts) do
    Output.print_error("Missing project path")
    IO.puts("Usage: albedo #{@cmd_resume} /path/to/project")
    IO.puts("   or: albedo #{@cmd_resume} ~/.albedo/projects/<project_id>")
    halt_with_error(1)
  end

  defp run_command([@cmd_resume, project_path | _], _opts) do
    Commands.Analysis.resume(project_path)
  end

  defp run_command([@cmd_projects | subcommand], opts) do
    Commands.Projects.dispatch(subcommand, opts)
  end

  defp run_command([@cmd_show], _opts) do
    Output.print_error("Missing project ID")
    IO.puts("Usage: albedo #{@cmd_show} <project_id>")
    halt_with_error(1)
  end

  defp run_command([@cmd_show, project_id | _], _opts) do
    Commands.Misc.show(project_id)
  end

  defp run_command([@cmd_replan], _opts) do
    Output.print_error("Missing project path")
    IO.puts("Usage: albedo #{@cmd_replan} /path/to/project --task \"New task description\"")
    halt_with_error(1)
  end

  defp run_command([@cmd_replan, project_path | _], opts) do
    Commands.Analysis.replan(project_path, opts)
  end

  defp run_command([@cmd_plan | _], opts) do
    Commands.Analysis.plan(opts)
  end

  defp run_command([@cmd_config | subcommand], _opts) do
    Commands.Config.dispatch(subcommand)
  end

  defp run_command([@cmd_path, project_id | _], _opts) do
    Commands.Misc.path(project_id)
  end

  defp run_command([@cmd_path], _opts) do
    Output.print_error("Missing project ID")
    Output.print_info("Usage: albedo #{@cmd_path} <project_id>")
    Output.print_info("Then:  cd $(albedo #{@cmd_path} <project_id>)")
    halt_with_error(1)
  end

  defp run_command([@cmd_tickets | subcommand], opts) do
    {extra_opts, remaining, _} =
      OptionParser.parse(subcommand,
        strict: [
          project: :string,
          status: :string,
          json: :boolean,
          format: :string,
          output: :string,
          all: :boolean,
          priority: :string,
          points: :integer,
          title: :string,
          description: :string,
          type: :string,
          labels: :string,
          yes: :boolean
        ]
      )

    merged_opts = Keyword.merge(opts, extra_opts)
    Commands.Tickets.dispatch(remaining, merged_opts)
  end

  defp run_command([@cmd_tui | _], _opts) do
    Commands.Misc.tui()
  end

  defp run_command([unknown | _], _opts) do
    Output.print_error("Unknown command: #{unknown}")
    Output.print_help()
    halt_with_error(1)
  end
end
