defmodule Albedo.CLI do
  @moduledoc """
  Command-line interface for Albedo.
  Parses arguments and dispatches to appropriate commands.
  """

  alias Albedo.CLI.{Commands, Output}

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
          yes: :boolean
        ],
        aliases: [
          h: :help,
          v: :version,
          t: :task,
          i: :interactive,
          n: :name,
          P: :project,
          f: :format,
          o: :output,
          p: :priority,
          d: :description,
          y: :yes
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

  defp run_command(["help" | _], _opts) do
    Output.print_help()
  end

  defp run_command(["init" | _], _opts) do
    Commands.Analysis.init()
  end

  defp run_command(["analyze"], _opts) do
    Output.print_error("Missing codebase path")
    IO.puts("Usage: albedo analyze /path/to/codebase --task \"Description of what to build\"")
    halt_with_error(1)
  end

  defp run_command(["analyze", path | _], opts) do
    Commands.Analysis.analyze(path, opts)
  end

  defp run_command(["resume"], _opts) do
    Output.print_error("Missing project path")
    IO.puts("Usage: albedo resume /path/to/project")
    IO.puts("   or: albedo resume ~/.albedo/projects/<project_id>")
    halt_with_error(1)
  end

  defp run_command(["resume", project_path | _], _opts) do
    Commands.Analysis.resume(project_path)
  end

  defp run_command(["projects" | subcommand], opts) do
    Commands.Projects.dispatch(subcommand, opts)
  end

  defp run_command(["show"], _opts) do
    Output.print_error("Missing project ID")
    IO.puts("Usage: albedo show <project_id>")
    halt_with_error(1)
  end

  defp run_command(["show", project_id | _], _opts) do
    Commands.Misc.show(project_id)
  end

  defp run_command(["replan"], _opts) do
    Output.print_error("Missing project path")
    IO.puts("Usage: albedo replan /path/to/project --task \"New task description\"")
    halt_with_error(1)
  end

  defp run_command(["replan", project_path | _], opts) do
    Commands.Analysis.replan(project_path, opts)
  end

  defp run_command(["plan" | _], opts) do
    Commands.Analysis.plan(opts)
  end

  defp run_command(["config" | subcommand], _opts) do
    Commands.Config.dispatch(subcommand)
  end

  defp run_command(["path", project_id | _], _opts) do
    Commands.Misc.path(project_id)
  end

  defp run_command(["path"], _opts) do
    Output.print_error("Missing project ID")
    Output.print_info("Usage: albedo path <project_id>")
    Output.print_info("Then:  cd $(albedo path <project_id>)")
    halt_with_error(1)
  end

  defp run_command(["tickets" | subcommand], opts) do
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
        ],
        aliases: [
          P: :project,
          f: :format,
          o: :output,
          p: :priority,
          t: :title,
          d: :description,
          y: :yes
        ]
      )

    merged_opts = Keyword.merge(opts, extra_opts)
    Commands.Tickets.dispatch(remaining, merged_opts)
  end

  defp run_command(["tui" | _], _opts) do
    Commands.Misc.tui()
  end

  defp run_command([unknown | _], _opts) do
    Output.print_error("Unknown command: #{unknown}")
    Output.print_help()
    halt_with_error(1)
  end
end
