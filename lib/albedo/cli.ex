defmodule Albedo.CLI do
  @moduledoc """
  Command-line interface for Albedo.
  Parses arguments and dispatches to appropriate commands.
  """

  alias Albedo.{Config, Session}

  @version Mix.Project.config()[:version]

  @doc """
  Main entry point for the CLI.
  """
  def main(args) do
    args
    |> parse_args()
    |> run()
  end

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
          output: :string,
          project: :string,
          scope: :string,
          stack: :string,
          database: :string,
          name: :string
        ],
        aliases: [
          h: :help,
          v: :version,
          t: :task,
          i: :interactive,
          o: :output,
          p: :project,
          s: :scope,
          n: :name
        ]
      )

    {opts, args, invalid}
  end

  defp run({opts, args, invalid}) do
    cond do
      invalid != [] ->
        print_invalid_args(invalid)
        halt_with_error(1)

      opts[:help] ->
        print_help()

      opts[:version] ->
        print_version()

      true ->
        run_command(args, opts)
    end
  end

  defp run_command([], _opts) do
    print_help()
  end

  defp run_command(["init" | _], _opts) do
    cmd_init()
  end

  defp run_command(["analyze", path | _], opts) do
    cmd_analyze(path, opts)
  end

  defp run_command(["resume", session_path | _], _opts) do
    cmd_resume(session_path)
  end

  defp run_command(["sessions" | _], _opts) do
    cmd_sessions()
  end

  defp run_command(["show", session_id | _], _opts) do
    cmd_show(session_id)
  end

  defp run_command(["replan", session_path | _], opts) do
    cmd_replan(session_path, opts)
  end

  defp run_command(["plan" | _], opts) do
    cmd_plan(opts)
  end

  defp run_command([unknown | _], _opts) do
    print_error("Unknown command: #{unknown}")
    print_help()
    halt_with_error(1)
  end

  defp cmd_init do
    print_header()
    print_info("Initializing Albedo configuration...")

    case Config.init() do
      {:ok, config_file} ->
        print_success("Configuration initialized!")
        print_info("Config file: #{config_file}")
        print_info("Sessions dir: #{Config.sessions_dir()}")
        IO.puts("")
        maybe_setup_api_key()

      {:error, reason} ->
        print_error("Failed to initialize: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp maybe_setup_api_key do
    case prompt_yes_no("Would you like to set up an API key now?", true) do
      true -> setup_api_key()
      false -> print_info("You can set up an API key later by running 'albedo init' again.")
    end
  end

  defp setup_api_key do
    IO.puts("")
    print_info("Albedo supports: Gemini (free tier), Claude, and OpenAI")
    IO.puts("")

    provider = prompt_provider()
    {env_var, get_key_url} = provider_info(provider)

    IO.puts("")
    print_info("Get your API key from: #{get_key_url}")
    IO.puts("")

    case prompt_string("Enter your #{provider} API key (or press Enter to skip)") do
      "" ->
        print_info("Skipped. You can add the API key to your shell profile later:")
        print_info("  export #{env_var}=\"your-api-key\"")

      api_key ->
        add_api_key_to_shell(env_var, api_key, provider)
    end
  end

  defp prompt_provider do
    IO.puts("Select a provider:")
    IO.puts("  1. Gemini (recommended - free tier available)")
    IO.puts("  2. Claude")
    IO.puts("  3. OpenAI")
    IO.puts("")

    case prompt_string("Enter choice [1]") do
      "" -> "Gemini"
      "1" -> "Gemini"
      "2" -> "Claude"
      "3" -> "OpenAI"
      _ -> prompt_provider()
    end
  end

  defp provider_info("Gemini"), do: {"GEMINI_API_KEY", "https://aistudio.google.com"}
  defp provider_info("Claude"), do: {"ANTHROPIC_API_KEY", "https://console.anthropic.com"}
  defp provider_info("OpenAI"), do: {"OPENAI_API_KEY", "https://platform.openai.com"}

  defp add_api_key_to_shell(env_var, api_key, provider) do
    shell_profile = detect_shell_profile()
    export_line = "export #{env_var}=\"#{api_key}\""

    IO.puts("")
    print_info("The following line will be added to #{shell_profile}:")
    IO.puts("")
    Owl.IO.puts(Owl.Data.tag("  #{export_line}", :cyan))
    IO.puts("")

    case prompt_yes_no("Proceed?", true) do
      true ->
        case append_to_shell_profile(shell_profile, env_var, export_line) do
          :ok ->
            update_config_provider(provider)
            IO.puts("")
            print_success("API key added to #{shell_profile}")
            IO.puts("")
            print_info("To use it now, run:")
            Owl.IO.puts(Owl.Data.tag("  source #{shell_profile}", :cyan))
            IO.puts("")
            print_info("Or restart your terminal.")

          {:already_exists, _} ->
            print_info("#{env_var} already exists in #{shell_profile}. Skipping.")

          {:error, reason} ->
            print_error("Failed to write to #{shell_profile}: #{inspect(reason)}")
            print_info("You can add it manually:")
            print_info("  echo '#{export_line}' >> #{shell_profile}")
        end

      false ->
        print_info("Skipped. You can add it manually:")
        print_info("  echo '#{export_line}' >> #{shell_profile}")
    end
  end

  defp detect_shell_profile do
    home = System.get_env("HOME") || "~"
    zshrc = Path.join(home, ".zshrc")
    bashrc = Path.join(home, ".bashrc")
    bash_profile = Path.join(home, ".bash_profile")

    cond do
      File.exists?(zshrc) -> zshrc
      File.exists?(bashrc) -> bashrc
      File.exists?(bash_profile) -> bash_profile
      true -> zshrc
    end
  end

  defp append_to_shell_profile(path, env_var, export_line) do
    case File.read(path) do
      {:ok, content} ->
        if String.contains?(content, env_var) do
          {:already_exists, path}
        else
          line_to_add = "\n# Added by Albedo\n#{export_line}\n"
          File.write(path, content <> line_to_add)
        end

      {:error, :enoent} ->
        line_to_add = "# Added by Albedo\n#{export_line}\n"
        File.write(path, line_to_add)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_config_provider(provider) do
    provider_key =
      case provider do
        "Gemini" -> "gemini"
        "Claude" -> "claude"
        "OpenAI" -> "openai"
      end

    config_file = Config.config_file()

    case File.read(config_file) do
      {:ok, content} ->
        updated =
          String.replace(content, ~r/provider = "[^"]*"/, "provider = \"#{provider_key}\"")

        File.write(config_file, updated)

      _ ->
        :ok
    end
  end

  defp prompt_yes_no(question, default) do
    default_hint = if default, do: "Y/n", else: "y/N"

    case prompt_string("#{question} [#{default_hint}]") do
      "" -> default
      input -> String.downcase(input) in ["y", "yes"]
    end
  end

  defp prompt_string(prompt) do
    IO.write("#{prompt}: ")

    case IO.read(:stdio, :line) do
      {:error, _} -> ""
      :eof -> ""
      line -> String.trim(line)
    end
  end

  defp cmd_analyze(path, opts) do
    print_header()

    path = Path.expand(path)
    task = opts[:task]

    unless task do
      print_error("Missing required --task option")

      print_info(
        "Usage: albedo analyze /path/to/codebase --task \"Description of what to build\""
      )

      halt_with_error(1)
    end

    unless File.dir?(path) do
      print_error("Codebase not found at: #{path}")
      halt_with_error(1)
    end

    print_info("Codebase: #{path}")
    print_info("Task: #{task}")
    print_separator()

    case Session.start(path, task, opts) do
      {:ok, session_id, result} ->
        print_success("\nAnalysis complete!")
        print_info("Session: #{session_id}")
        print_info("Output: #{result.output_path}")
        print_summary(result)

      {:error, {:phase_failed, session_id, session_dir}} ->
        print_error("Analysis failed during a phase")
        print_info("Session: #{session_id}")
        print_info("You can retry with: albedo resume #{session_dir}")
        halt_with_error(1)

      {:error, reason} ->
        print_error("Analysis failed: #{format_error(reason)}")
        halt_with_error(1)
    end
  end

  defp cmd_resume(session_path) do
    print_header()
    session_path = Path.expand(session_path)

    unless File.dir?(session_path) do
      print_error("Session not found at: #{session_path}")
      halt_with_error(1)
    end

    print_info("Resuming session: #{session_path}")

    case Session.resume(session_path) do
      {:ok, session_id, result} ->
        print_success("\nAnalysis complete!")
        print_info("Session: #{session_id}")
        print_info("Output: #{result.output_path}")
        print_summary(result)

      {:error, reason} ->
        print_error("Resume failed: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp cmd_sessions do
    print_header()
    config = Config.load!()
    sessions_dir = Config.session_dir(config)

    case File.ls(sessions_dir) do
      {:ok, sessions} ->
        sessions = Enum.sort(sessions, :desc)

        if Enum.empty?(sessions) do
          print_info("No sessions found.")
        else
          print_info("Recent sessions:")
          print_separator()

          Enum.each(sessions, fn session ->
            session_file = Path.join([sessions_dir, session, "session.json"])

            if File.exists?(session_file) do
              case File.read(session_file) do
                {:ok, content} ->
                  case Jason.decode(content) do
                    {:ok, data} ->
                      state = data["state"] || "unknown"
                      task = data["task"] || "No task"
                      task = String.slice(task, 0, 60)
                      print_session(session, state, task)

                    _ ->
                      print_session(session, "?", "")
                  end

                _ ->
                  print_session(session, "?", "")
              end
            else
              print_session(session, "?", "")
            end
          end)
        end

      {:error, :enoent} ->
        print_info("No sessions directory found. Run 'albedo init' first.")

      {:error, reason} ->
        print_error("Failed to list sessions: #{inspect(reason)}")
    end
  end

  defp cmd_show(session_id) do
    print_header()
    config = Config.load!()
    session_path = Path.join(Config.session_dir(config), session_id)

    unless File.dir?(session_path) do
      print_error("Session not found: #{session_id}")
      halt_with_error(1)
    end

    feature_file = Path.join(session_path, "FEATURE.md")

    if File.exists?(feature_file) do
      case File.read(feature_file) do
        {:ok, content} ->
          IO.puts(content)

        {:error, reason} ->
          print_error("Failed to read FEATURE.md: #{inspect(reason)}")
      end
    else
      print_info("Session #{session_id} does not have a FEATURE.md yet.")
      print_info("The session may be incomplete. Try 'albedo resume #{session_path}'")
    end
  end

  defp cmd_replan(session_path, opts) do
    print_header()
    session_path = Path.expand(session_path)

    unless File.dir?(session_path) do
      print_error("Session not found at: #{session_path}")
      halt_with_error(1)
    end

    scope = opts[:scope] || "full"
    print_info("Re-planning session: #{session_path}")
    print_info("Scope: #{scope}")

    case Session.replan(session_path, opts) do
      {:ok, session_id, result} ->
        print_success("\nRe-planning complete!")
        print_info("Session: #{session_id}")
        print_info("Output: #{result.output_path}")
        print_summary(result)

      {:error, reason} ->
        print_error("Re-planning failed: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp cmd_plan(opts) do
    print_header()

    task = opts[:task]
    project_name = opts[:name]
    stack = opts[:stack]

    unless task do
      print_error("Missing required --task option")
      print_info("Usage: albedo plan --task \"Build a todo app\" --name my_app --stack phoenix")
      halt_with_error(1)
    end

    unless project_name do
      print_error("Missing required --name option")
      print_info("Usage: albedo plan --task \"Build a todo app\" --name my_app --stack phoenix")
      halt_with_error(1)
    end

    print_info("Planning new project: #{project_name}")
    print_info("Task: #{task}")

    if stack do
      print_info("Stack: #{stack}")
    end

    if opts[:database] do
      print_info("Database: #{opts[:database]}")
    end

    print_separator()

    greenfield_opts = Keyword.merge(opts, greenfield: true)

    case Session.start_greenfield(project_name, task, greenfield_opts) do
      {:ok, session_id, result} ->
        print_success("\nPlanning complete!")
        print_info("Session: #{session_id}")
        print_info("Output: #{result.output_path}")
        print_greenfield_summary(result)

      {:error, {:phase_failed, session_id, session_dir}} ->
        print_error("Planning failed during a phase")
        print_info("Session: #{session_id}")
        print_info("You can retry with: albedo resume #{session_dir}")
        halt_with_error(1)

      {:error, reason} ->
        print_error("Planning failed: #{format_error(reason)}")
        halt_with_error(1)
    end
  end

  defp format_error(:rate_limited) do
    "API rate limit exceeded. Wait a minute and try again, or configure a fallback provider."
  end

  defp format_error(:no_fallback_configured) do
    "Rate limited and no fallback provider configured. Add a fallback in ~/.albedo/config.toml"
  end

  defp format_error(:max_retries_exceeded),
    do: "Request failed after retries. Check your network connection."

  defp format_error(:timeout), do: "Request timed out. Check your network connection."
  defp format_error({:http_error, status}), do: "HTTP error: #{status}"
  defp format_error(reason), do: inspect(reason)

  defp print_header do
    Owl.IO.puts([
      Owl.Data.tag("Albedo", :cyan),
      " ",
      Owl.Data.tag("v#{@version}", :light_black),
      "\n",
      String.duplicate("━", 50),
      "\n"
    ])
  end

  defp print_separator do
    IO.puts(String.duplicate("─", 50))
  end

  defp print_info(message) do
    Owl.IO.puts(Owl.Data.tag(message, :light_black))
  end

  defp print_success(message) do
    Owl.IO.puts(Owl.Data.tag("✓ #{message}", :green))
  end

  defp print_error(message) do
    Owl.IO.puts(Owl.Data.tag("✗ #{message}", :red))
  end

  defp print_session(id, state, task) do
    state_color =
      case state do
        "completed" -> :green
        "failed" -> :red
        "paused" -> :yellow
        _ -> :light_black
      end

    Owl.IO.puts([
      Owl.Data.tag("  #{id}", :cyan),
      "  ",
      Owl.Data.tag("[#{state}]", state_color),
      "  ",
      task
    ])
  end

  defp print_summary(result) do
    IO.puts("")
    Owl.IO.puts(Owl.Data.tag("Summary:", :cyan))

    if result[:tickets_count] do
      IO.puts("  • #{result.tickets_count} tickets generated")
    end

    if result[:total_points] do
      IO.puts("  • #{result.total_points} story points estimated")
    end

    if result[:files_to_create] && result[:files_to_create] > 0 do
      IO.puts("  • #{result.files_to_create} files to create")
    end

    if result[:files_to_modify] && result[:files_to_modify] > 0 do
      IO.puts("  • #{result.files_to_modify} files to modify")
    end

    if result[:risks_identified] && result[:risks_identified] > 0 do
      IO.puts("  • #{result.risks_identified} risks identified")
    end

    print_next_steps(result)
  end

  defp print_greenfield_summary(result) do
    IO.puts("")
    Owl.IO.puts(Owl.Data.tag("Summary:", :cyan))

    if result[:tickets_count] do
      IO.puts("  • #{result.tickets_count} tickets generated")
    end

    if result[:total_points] do
      IO.puts("  • #{result.total_points} story points estimated")
    end

    if result[:files_to_create] do
      IO.puts("  • #{result.files_to_create} files to create")
    end

    if result[:recommended_stack] do
      IO.puts("  • Recommended stack: #{result.recommended_stack}")
    end

    if result[:setup_steps] && result[:setup_steps] > 0 do
      IO.puts("  • #{result.setup_steps} setup steps")
    end

    print_next_steps(result)
  end

  defp print_next_steps(result) do
    IO.puts("")
    Owl.IO.puts(Owl.Data.tag("Next Steps:", :cyan))
    IO.puts("  1. View the plan:        cat #{result.output_path}")
    IO.puts("  2. Go to session folder: cd #{Path.dirname(result.output_path)}")
    IO.puts("  3. View in CLI:          albedo show #{result.session_id}")
  end

  defp print_invalid_args(invalid) do
    Enum.each(invalid, fn {arg, _} ->
      print_error("Invalid option: #{arg}")
    end)
  end

  defp print_help do
    Owl.IO.puts([
      Owl.Data.tag("Albedo", :cyan),
      " - Codebase-to-Tickets CLI Tool\n\n",
      Owl.Data.tag("USAGE:", :yellow),
      "\n    albedo <command> [options]\n\n",
      Owl.Data.tag("COMMANDS:", :yellow),
      """

          init                    Initialize configuration (first-time setup)
          analyze <path>          Analyze a codebase with a task
          plan                    Plan a new project from scratch (greenfield)
          resume <session_path>   Resume an incomplete session
          sessions                List recent sessions
          show <session_id>       View a session's output
          replan <session_path>   Re-run planning phase with different parameters

      """,
      Owl.Data.tag("OPTIONS:", :yellow),
      """

          -t, --task <desc>       Task description (required for analyze/plan)
          -n, --name <name>       Project name (required for plan)
          --stack <stack>         Tech stack: phoenix, rails, nextjs, fastapi, etc.
          --database <db>         Database: postgres, mysql, sqlite, mongodb
          -i, --interactive       Enable interactive clarifying questions
          -o, --output <format>   Output format: markdown (default), linear, jira
          -p, --project <name>    Project name for ticket system integration
          -s, --scope <scope>     Planning scope: full (default), minimal
          -h, --help              Show this help message
          -v, --version           Show version

      """,
      Owl.Data.tag("EXAMPLES:", :yellow),
      """

          # Analyze existing codebase
          albedo analyze ~/projects/myapp --task "Add user authentication"
          albedo analyze . -t "Convert status to configurable dropdown" -i

          # Plan new project from scratch
          albedo plan --name my_todo --task "Build a todo app with user accounts"
          albedo plan -n shop_api -t "E-commerce API" --stack phoenix --database postgres

          # Session management
          albedo sessions
          albedo show 2024-12-24_user-auth
          albedo resume ~/.albedo/sessions/2024-12-24_user-auth/

      """,
      Owl.Data.tag("CONFIGURATION:", :yellow),
      """

          Config file: ~/.albedo/config.toml
          Sessions:    ~/.albedo/sessions/
      """
    ])
  end

  defp print_version do
    IO.puts("Albedo v#{@version}")
  end
end
