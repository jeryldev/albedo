defmodule Albedo.CLI.Commands.Analysis do
  @moduledoc """
  CLI commands for analysis operations.
  Handles init, analyze, resume, replan, and plan commands.
  """

  alias Albedo.CLI.Output
  alias Albedo.{Config, Project}

  @spec init() :: :ok | no_return()
  def init do
    Output.print_header()

    IO.puts("Checking prerequisites...")
    IO.puts("")

    elixir_version = System.version()
    otp_version = :erlang.system_info(:otp_release) |> List.to_string()
    install_method = check_elixir_install_method()

    install_method_label =
      case install_method do
        :asdf -> "asdf"
        :homebrew -> "Homebrew"
        :system -> "system"
      end

    Output.print_success(
      "Elixir #{elixir_version} (OTP #{otp_version}) via #{install_method_label}"
    )

    ripgrep_status = Output.check_ripgrep()

    IO.puts("")

    case Config.init() do
      {:ok, config_file} ->
        Output.print_success("Config directory ready!")
        Output.print_info("Config file: #{config_file}")
        Output.print_info("Projects dir: #{Config.projects_dir()}")
        IO.puts("")

        config = Config.load!()
        provider = Config.provider(config)
        api_key = Config.api_key(config)

        IO.puts("Current configuration:")
        IO.puts("  Provider: #{provider}")

        if api_key do
          Output.print_success("API key is set")
        else
          env_var = Config.env_var_for_provider(provider)
          Owl.IO.puts(["  API Key: ", Owl.Data.tag("NOT SET", :red)])
          IO.puts("")
          Output.print_info("If you just ran install.sh, activate your shell first:")
          IO.puts("  source ~/.zshrc  # or ~/.bashrc")
          IO.puts("")
          Output.print_info("Otherwise, set your API key:")
          IO.puts("  albedo config set-key")
          IO.puts("")
          Output.print_info("Or manually add to your shell profile:")
          IO.puts("  export #{env_var}=\"your-api-key\"")
        end

        IO.puts("")
        Output.print_info("To change provider: albedo config set-provider")
        Output.print_info("To view config:     albedo config")

        if ripgrep_status == :missing do
          IO.puts("")
          Output.print_warning("Albedo requires ripgrep for codebase analysis.")
          Output.print_info("Please install ripgrep before using 'albedo analyze'.")
        end

      {:error, reason} ->
        Output.print_error("Failed to initialize: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  @spec analyze(String.t(), keyword()) :: :ok | no_return()
  def analyze(path, opts) do
    Output.print_header()

    path = Path.expand(path)
    task = opts[:task]

    unless task do
      Output.print_error("Missing required --task option")

      Output.print_info(
        "Usage: albedo analyze /path/to/codebase --task \"Description of what to build\""
      )

      halt_with_error(1)
    end

    unless File.dir?(path) do
      Output.print_error("Codebase not found at: #{path}")
      halt_with_error(1)
    end

    Output.print_info("Codebase: #{path}")
    Output.print_info("Task: #{task}")
    Output.print_separator()

    case Project.start(path, task, opts) do
      {:ok, project_id, result} ->
        Output.print_success("\nAnalysis complete!")
        Output.print_info("Project: #{project_id}")
        Output.print_info("Output: #{result.output_path}")
        Output.print_summary(result)

      {:error, {:phase_failed, project_id, project_dir}} ->
        Output.print_error("Analysis failed during a phase")
        Output.print_info("Project: #{project_id}")
        Output.print_info("You can retry with: albedo resume #{project_dir}")
        halt_with_error(1)

      {:error, reason} ->
        Output.print_error("Analysis failed: #{Output.format_error(reason)}")
        halt_with_error(1)
    end
  end

  @spec resume(String.t()) :: :ok | no_return()
  def resume(project_path) do
    Output.print_header()
    project_path = Path.expand(project_path)

    unless File.dir?(project_path) do
      Output.print_error("Project not found at: #{project_path}")
      halt_with_error(1)
    end

    Output.print_info("Resuming project: #{project_path}")

    case Project.resume(project_path) do
      {:ok, project_id, result} ->
        Output.print_success("\nAnalysis complete!")
        Output.print_info("Project: #{project_id}")
        Output.print_info("Output: #{result.output_path}")
        Output.print_summary(result)

      {:error, reason} ->
        Output.print_error("Resume failed: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  @spec replan(String.t(), keyword()) :: :ok | no_return()
  def replan(project_path, opts) do
    Output.print_header()
    project_path = Path.expand(project_path)

    unless File.dir?(project_path) do
      Output.print_error("Project not found at: #{project_path}")
      halt_with_error(1)
    end

    scope = opts[:scope] || "full"
    Output.print_info("Re-planning project: #{project_path}")
    Output.print_info("Scope: #{scope}")

    case Project.replan(project_path, opts) do
      {:ok, project_id, result} ->
        Output.print_success("\nRe-planning complete!")
        Output.print_info("Project: #{project_id}")
        Output.print_info("Output: #{result.output_path}")
        Output.print_summary(result)

      {:error, reason} ->
        Output.print_error("Re-planning failed: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  @spec plan(keyword()) :: :ok | no_return()
  def plan(opts) do
    Output.print_header()

    task = opts[:task]
    project_name = opts[:name]
    stack = opts[:stack]

    unless task do
      Output.print_error("Missing required --task option")

      Output.print_info(
        "Usage: albedo plan --task \"Build a todo app\" --name my_app --stack phoenix"
      )

      halt_with_error(1)
    end

    unless project_name do
      Output.print_error("Missing required --name option")

      Output.print_info(
        "Usage: albedo plan --task \"Build a todo app\" --name my_app --stack phoenix"
      )

      halt_with_error(1)
    end

    Output.print_info("Planning new project: #{project_name}")
    Output.print_info("Task: #{task}")

    if stack do
      Output.print_info("Stack: #{stack}")
    end

    if opts[:database] do
      Output.print_info("Database: #{opts[:database]}")
    end

    Output.print_separator()

    greenfield_opts = Keyword.merge(opts, greenfield: true)

    case Project.start_greenfield(project_name, task, greenfield_opts) do
      {:ok, project_id, result} ->
        Output.print_success("\nPlanning complete!")
        Output.print_info("Project: #{project_id}")
        Output.print_info("Output: #{result.output_path}")
        Output.print_greenfield_summary(result)

      {:error, {:phase_failed, project_id, project_dir}} ->
        Output.print_error("Planning failed during a phase")
        Output.print_info("Project: #{project_id}")
        Output.print_info("You can retry with: albedo resume #{project_dir}")
        halt_with_error(1)

      {:error, reason} ->
        Output.print_error("Planning failed: #{Output.format_error(reason)}")
        halt_with_error(1)
    end
  end

  defp check_elixir_install_method do
    cond do
      System.find_executable("asdf") != nil ->
        :asdf

      System.find_executable("brew") != nil ->
        :homebrew

      true ->
        :system
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
