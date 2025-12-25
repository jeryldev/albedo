defmodule Albedo.CLI do
  @moduledoc """
  Command-line interface for Albedo.
  Parses arguments and dispatches to appropriate commands.
  """

  alias Albedo.{Config, Session, Tickets}
  alias Albedo.Tickets.Exporter

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
          scope: :string,
          stack: :string,
          database: :string,
          name: :string,
          session: :string,
          status: :string,
          json: :boolean,
          format: :string,
          output: :string,
          all: :boolean
        ],
        aliases: [
          h: :help,
          v: :version,
          t: :task,
          i: :interactive,
          n: :name,
          s: :session,
          f: :format,
          o: :output
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

  defp run_command(["help" | _], _opts) do
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

  defp run_command(["config" | subcommand], _opts) do
    cmd_config(subcommand)
  end

  defp run_command(["path", session_id | _], _opts) do
    cmd_path(session_id)
  end

  defp run_command(["path"], _opts) do
    print_error("Missing session ID")
    print_info("Usage: albedo path <session_id>")
    print_info("Then:  cd $(albedo path <session_id>)")
    halt_with_error(1)
  end

  defp run_command(["tickets" | subcommand], opts) do
    {extra_opts, remaining, _} =
      OptionParser.parse(subcommand,
        strict: [
          session: :string,
          status: :string,
          json: :boolean,
          format: :string,
          output: :string,
          all: :boolean
        ],
        aliases: [s: :session, f: :format, o: :output]
      )

    merged_opts = Keyword.merge(opts, extra_opts)
    cmd_tickets(remaining, merged_opts)
  end

  defp run_command([unknown | _], _opts) do
    print_error("Unknown command: #{unknown}")
    print_help()
    halt_with_error(1)
  end

  defp cmd_init do
    print_header()

    case Config.init() do
      {:ok, config_file} ->
        print_success("Config directory ready!")
        print_info("Config file: #{config_file}")
        print_info("Sessions dir: #{Config.sessions_dir()}")
        IO.puts("")

        config = Config.load!()
        provider = Config.provider(config)
        api_key = Config.api_key(config)

        IO.puts("Current configuration:")
        IO.puts("  Provider: #{provider}")

        if api_key do
          print_success("API key is set")
        else
          env_var = Config.env_var_for_provider(provider)
          Owl.IO.puts(["  API Key: ", Owl.Data.tag("NOT SET", :red)])
          IO.puts("")
          print_info("To set your API key, run:")
          IO.puts("  albedo config set-key")
          IO.puts("")
          print_info("Or manually add to your shell profile:")
          IO.puts("  export #{env_var}=\"your-api-key\"")
        end

        IO.puts("")
        print_info("To change provider: albedo config set-provider")
        print_info("To view config:     albedo config")

      {:error, reason} ->
        print_error("Failed to initialize: #{inspect(reason)}")
        halt_with_error(1)
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

  defp cmd_config([]) do
    cmd_config(["show"])
  end

  defp cmd_config(["show" | _]) do
    print_header()
    config = Config.load!()

    provider = Config.provider(config)
    api_key = Config.api_key(config)
    model = Config.model(config)

    Owl.IO.puts(Owl.Data.tag("Current Configuration:", :cyan))
    IO.puts("")

    IO.puts("  Provider:   #{provider}")
    IO.puts("  Model:      #{model}")

    if api_key do
      masked = mask_api_key(api_key)
      Owl.IO.puts(["  API Key:    ", Owl.Data.tag(masked, :green)])
    else
      Owl.IO.puts(["  API Key:    ", Owl.Data.tag("NOT SET", :red)])
    end

    IO.puts("")
    IO.puts("  Config:     #{Config.config_file()}")
    IO.puts("  Sessions:   #{Config.sessions_dir()}")
  end

  defp cmd_config(["set-provider" | _]) do
    print_header()

    IO.puts("Select LLM provider:")
    IO.puts("")
    IO.puts("  1. Gemini (recommended - free tier available)")
    IO.puts("  2. Claude")
    IO.puts("  3. OpenAI")
    IO.puts("")

    choice = IO.gets("Enter choice [1]: ") |> String.trim()

    provider =
      case choice do
        "2" -> "claude"
        "3" -> "openai"
        _ -> "gemini"
      end

    env_var = Config.env_var_for_provider(provider)

    IO.puts("")
    IO.puts("This will update #{Config.config_file()}:")
    Owl.IO.puts(Owl.Data.tag("  provider = \"#{provider}\"", :cyan))
    IO.puts("")

    confirm = IO.gets("Proceed? [Y/n]: ") |> String.trim() |> String.downcase()

    if confirm in ["", "y", "yes"] do
      case Config.set_provider(provider) do
        :ok ->
          print_success("Provider set to #{provider}")
          IO.puts("")
          print_info("Make sure you have #{env_var} set in your shell profile.")
          print_info("Run: albedo config set-key")

        {:error, reason} ->
          print_error("Failed to update config: #{inspect(reason)}")
          halt_with_error(1)
      end
    else
      print_info("Cancelled.")
    end
  end

  defp cmd_config(["set-key" | _]) do
    print_header()

    config = Config.load!()
    provider = Config.provider(config)
    env_var = Config.env_var_for_provider(provider)

    IO.puts("Current provider: #{provider}")
    IO.puts("Environment variable: #{env_var}")
    IO.puts("")

    api_key = IO.gets("Enter your API key: ") |> String.trim()

    if api_key == "" do
      print_info("Cancelled.")
    else
      shell_profile = detect_shell_profile()
      masked = mask_api_key(api_key)
      export_line = "export #{env_var}=\"#{api_key}\""

      IO.puts("")
      IO.puts("This will update #{shell_profile}:")
      Owl.IO.puts(Owl.Data.tag("  export #{env_var}=\"#{masked}\"", :cyan))
      IO.puts("")

      confirm = IO.gets("Proceed? [Y/n]: ") |> String.trim() |> String.downcase()

      if confirm in ["", "y", "yes"] do
        case append_to_shell_profile(shell_profile, env_var, export_line) do
          {:ok, :replaced} ->
            print_success("Replaced #{env_var} in #{shell_profile}")
            IO.puts("")
            print_info("Run: source #{shell_profile}")

          {:ok, :added} ->
            print_success("Added #{env_var} to #{shell_profile}")
            IO.puts("")
            print_info("Run: source #{shell_profile}")
        end
      else
        print_info("Cancelled.")
      end
    end
  end

  defp cmd_config([unknown | _]) do
    print_error("Unknown config subcommand: #{unknown}")
    IO.puts("")
    IO.puts("Available subcommands:")
    IO.puts("  albedo config show         Show current configuration")
    IO.puts("  albedo config set-provider Select LLM provider")
    IO.puts("  albedo config set-key      Set API key for current provider")
    halt_with_error(1)
  end

  defp cmd_path(session_id) do
    config = Config.load!()
    session_path = Path.join(Config.session_dir(config), session_id)

    if File.dir?(session_path) do
      IO.puts(session_path)
    else
      IO.puts(:stderr, "Session not found: #{session_id}")
      halt_with_error(1)
    end
  end

  defp cmd_tickets([], opts) do
    cmd_tickets(["list"], opts)
  end

  defp cmd_tickets(["list" | _], opts) do
    print_header()
    session_dir = resolve_session_dir(opts)

    case Tickets.load(session_dir) do
      {:ok, data} ->
        tickets = Tickets.list(data, Keyword.take(opts, [:status]))
        print_ticket_list(data, tickets)

      {:error, :not_found} ->
        print_error("No tickets.json found for this session")
        print_info("Run 'albedo analyze' first to generate tickets")
        halt_with_error(1)

      {:error, reason} ->
        print_error("Failed to load tickets: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp cmd_tickets(["show", id | _], opts) do
    print_header()
    session_dir = resolve_session_dir(opts)

    case Tickets.load(session_dir) do
      {:ok, data} ->
        case Tickets.get(data, id) do
          nil ->
            print_error("Ticket ##{id} not found")
            halt_with_error(1)

          ticket ->
            if opts[:json] do
              ticket |> Tickets.Ticket.to_json() |> Jason.encode!(pretty: true) |> IO.puts()
            else
              print_ticket_detail(ticket)
            end
        end

      {:error, :not_found} ->
        print_error("No tickets.json found for this session")
        halt_with_error(1)

      {:error, reason} ->
        print_error("Failed to load tickets: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp cmd_tickets(["start", id | _], opts) do
    update_ticket_status(id, :start, opts)
  end

  defp cmd_tickets(["done" | ids], opts) do
    Enum.each(ids, fn id ->
      update_ticket_status(id, :complete, opts)
    end)
  end

  defp cmd_tickets(["reset" | ids], opts) do
    if opts[:all] do
      reset_all_tickets(opts)
    else
      Enum.each(ids, fn id ->
        update_ticket_status(id, :reset, opts)
      end)
    end
  end

  defp cmd_tickets(["export" | _], opts) do
    export_tickets(opts)
  end

  defp cmd_tickets([unknown | _], _opts) do
    print_error("Unknown tickets subcommand: #{unknown}")
    IO.puts("")
    IO.puts("Available subcommands:")
    IO.puts("  albedo tickets                  List tickets from most recent session")
    IO.puts("  albedo tickets --session <id>   List tickets from specific session")
    IO.puts("  albedo tickets --status pending Filter by status")
    IO.puts("  albedo tickets show <id>        Show ticket details")
    IO.puts("  albedo tickets start <id>       Mark ticket as in_progress")
    IO.puts("  albedo tickets done <id> [ids]  Mark tickets as completed")
    IO.puts("  albedo tickets reset <id>       Reset ticket to pending")
    IO.puts("  albedo tickets reset --all      Reset all tickets")

    IO.puts(
      "  albedo tickets export           Export tickets (--format json|csv|markdown|github)"
    )

    halt_with_error(1)
  end

  defp update_ticket_status(id, action, opts) do
    session_dir = resolve_session_dir(opts)

    case Tickets.load(session_dir) do
      {:ok, data} ->
        action_fn =
          case action do
            :start -> &Tickets.start/2
            :complete -> &Tickets.complete/2
            :reset -> &Tickets.reset/2
          end

        case action_fn.(data, id) do
          {:ok, updated_data, ticket} ->
            case Tickets.save(session_dir, updated_data) do
              :ok ->
                action_str =
                  case action do
                    :start -> "started"
                    :complete -> "completed"
                    :reset -> "reset"
                  end

                print_success("Ticket ##{id} #{action_str}: #{ticket.title}")

              {:error, reason} ->
                print_error("Failed to save: #{inspect(reason)}")
                halt_with_error(1)
            end

          {:error, :not_found} ->
            print_error("Ticket ##{id} not found")
            halt_with_error(1)
        end

      {:error, :not_found} ->
        print_error("No tickets.json found for this session")
        halt_with_error(1)

      {:error, reason} ->
        print_error("Failed to load tickets: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp reset_all_tickets(opts) do
    session_dir = resolve_session_dir(opts)

    case Tickets.load(session_dir) do
      {:ok, data} ->
        updated_data = Tickets.reset_all(data)

        case Tickets.save(session_dir, updated_data) do
          :ok ->
            print_success("All tickets reset to pending")

          {:error, reason} ->
            print_error("Failed to save: #{inspect(reason)}")
            halt_with_error(1)
        end

      {:error, :not_found} ->
        print_error("No tickets.json found for this session")
        halt_with_error(1)

      {:error, reason} ->
        print_error("Failed to load tickets: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp export_tickets(opts) do
    print_header()
    session_dir = resolve_session_dir(opts)

    format_str = opts[:format] || "json"

    format =
      case format_str do
        "json" ->
          :json

        "csv" ->
          :csv

        "markdown" ->
          :markdown

        "md" ->
          :markdown

        "github" ->
          :github

        other ->
          print_error("Unknown format: #{other}")
          print_info("Available formats: json, csv, markdown, github")
          halt_with_error(1)
      end

    case Tickets.load(session_dir) do
      {:ok, data} ->
        export_opts =
          if opts[:status], do: [status: String.to_existing_atom(opts[:status])], else: []

        case Exporter.export(data, format, export_opts) do
          {:ok, content} ->
            output_path = opts[:output]

            if output_path do
              case File.write(output_path, content) do
                :ok ->
                  print_success("Exported #{length(data.tickets)} tickets to #{output_path}")
                  print_info("Format: #{Exporter.format_name(format)}")

                {:error, reason} ->
                  print_error("Failed to write file: #{inspect(reason)}")
                  halt_with_error(1)
              end
            else
              IO.puts(content)
            end

          {:error, reason} ->
            print_error("Export failed: #{inspect(reason)}")
            halt_with_error(1)
        end

      {:error, :not_found} ->
        print_error("No tickets.json found for this session")
        halt_with_error(1)

      {:error, reason} ->
        print_error("Failed to load tickets: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp resolve_session_dir(opts) do
    case opts[:session] do
      nil ->
        config = Config.load!()
        sessions_dir = Config.session_dir(config)

        case File.ls(sessions_dir) do
          {:ok, sessions} when sessions != [] ->
            most_recent = sessions |> Enum.sort(:desc) |> List.first()
            Path.join(sessions_dir, most_recent)

          _ ->
            print_error("No sessions found")
            halt_with_error(1)
        end

      session_id ->
        config = Config.load!()
        Path.join(Config.session_dir(config), session_id)
    end
  end

  defp print_ticket_list(data, tickets) do
    IO.puts("Session: #{data.session_id}")
    IO.puts("Task: #{String.slice(data.task_description || "", 0, 60)}")
    print_separator()
    IO.puts("")

    IO.puts("  #  Status       Pri   Est  Title")
    IO.puts("  ─  ──────       ───   ───  ─────")

    Enum.each(tickets, fn ticket ->
      status_symbol = status_symbol(ticket.status)
      status_str = ticket.status |> to_string() |> String.pad_trailing(10)
      priority_str = ticket.priority |> to_string() |> String.slice(0, 3)

      estimate_str =
        if ticket.estimate, do: String.pad_leading(to_string(ticket.estimate), 3), else: "  -"

      title = String.slice(ticket.title, 0, 40)

      status_color =
        case ticket.status do
          :completed -> :green
          :in_progress -> :yellow
          :pending -> :light_black
        end

      Owl.IO.puts([
        "  ",
        String.pad_leading(ticket.id, 2),
        "  ",
        Owl.Data.tag("#{status_symbol} #{status_str}", status_color),
        " ",
        priority_str,
        "   ",
        estimate_str,
        "  ",
        title
      ])
    end)

    IO.puts("")
    print_separator()

    summary = data.summary

    IO.puts(
      "Progress: #{summary.completed}/#{summary.total} tickets (#{summary.completed_points}/#{summary.total_points} points)"
    )

    IO.puts("")
    IO.puts("Commands:")
    IO.puts("  albedo tickets show 1     # View ticket details")
    IO.puts("  albedo tickets start 2    # Start working on ticket")
    IO.puts("  albedo tickets done 1     # Mark ticket complete")
  end

  defp print_ticket_detail(ticket) do
    Owl.IO.puts([
      "Ticket #",
      Owl.Data.tag(ticket.id, :cyan),
      ": ",
      ticket.title
    ])

    print_separator()
    IO.puts("")

    status_color =
      case ticket.status do
        :completed -> :green
        :in_progress -> :yellow
        :pending -> :light_black
      end

    Owl.IO.puts([
      "Status:     ",
      Owl.Data.tag("#{status_symbol(ticket.status)} #{ticket.status}", status_color)
    ])

    IO.puts("Type:       #{ticket.type}")
    IO.puts("Priority:   #{ticket.priority}")

    if ticket.estimate do
      IO.puts("Estimate:   #{ticket.estimate} points")
    end

    if ticket.labels != [] do
      IO.puts("Labels:     #{Enum.join(ticket.labels, ", ")}")
    end

    IO.puts("")

    if ticket.description do
      Owl.IO.puts(Owl.Data.tag("Description:", :cyan))
      IO.puts("  #{ticket.description}")
      IO.puts("")
    end

    if ticket.files.create != [] do
      Owl.IO.puts(Owl.Data.tag("Files to Create:", :cyan))
      Enum.each(ticket.files.create, &IO.puts("  • #{&1}"))
      IO.puts("")
    end

    if ticket.files.modify != [] do
      Owl.IO.puts(Owl.Data.tag("Files to Modify:", :cyan))
      Enum.each(ticket.files.modify, &IO.puts("  • #{&1}"))
      IO.puts("")
    end

    if ticket.acceptance_criteria != [] do
      Owl.IO.puts(Owl.Data.tag("Acceptance Criteria:", :cyan))

      Enum.each(ticket.acceptance_criteria, fn criterion ->
        clean_criterion = String.replace(criterion, ~r/^\s*\[[ x~]\]\s*/, "")
        IO.puts("  ☐ #{clean_criterion}")
      end)

      IO.puts("")
    end

    if ticket.dependencies.blocked_by != [] do
      IO.puts("Blocked by: ##{Enum.join(ticket.dependencies.blocked_by, ", #")}")
    end

    if ticket.dependencies.blocks != [] do
      IO.puts("Blocks: ##{Enum.join(ticket.dependencies.blocks, ", #")}")
    end
  end

  defp status_symbol(:pending), do: "○"
  defp status_symbol(:in_progress), do: "●"
  defp status_symbol(:completed), do: "✓"

  defp mask_api_key(key) when is_binary(key) and byte_size(key) > 12 do
    "#{String.slice(key, 0, 8)}...#{String.slice(key, -4, 4)}"
  end

  defp mask_api_key(key) when is_binary(key), do: "****"
  defp mask_api_key(_), do: "NOT SET"

  defp detect_shell_profile do
    shell = System.get_env("SHELL") || ""

    cond do
      String.contains?(shell, "zsh") -> "~/.zshrc"
      String.contains?(shell, "bash") -> "~/.bashrc"
      true -> "~/.profile"
    end
  end

  defp append_to_shell_profile(shell_profile, env_var, export_line) do
    path = Path.expand(shell_profile)

    if File.exists?(path) do
      content = File.read!(path)
      pattern = ~r/^export #{Regex.escape(env_var)}=.*$/m

      if Regex.match?(pattern, content) do
        updated = Regex.replace(pattern, content, export_line)
        File.write!(path, updated)
        {:ok, :replaced}
      else
        File.write!(path, content <> "\n# Added by Albedo\n#{export_line}\n")
        {:ok, :added}
      end
    else
      File.write!(path, "# Added by Albedo\n#{export_line}\n")
      {:ok, :added}
    end
  end

  defp format_error(:rate_limited) do
    "API rate limit exceeded. Wait a minute and try again."
  end

  defp format_error(:invalid_api_key) do
    "Invalid API key. Run 'albedo config set-key' to set your API key."
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
    IO.puts("  1. View the plan:        albedo show #{result.session_id}")
    IO.puts("  2. Manage tickets:       albedo tickets --session #{result.session_id}")
    IO.puts("  3. Go to session folder: cd $(albedo path #{result.session_id})")
  end

  defp print_invalid_args(invalid) do
    Enum.each(invalid, fn {arg, _} ->
      print_error("Invalid option: #{arg}")
    end)
  end

  defp print_help do
    Owl.IO.puts([
      Owl.Data.tag("Albedo", :cyan),
      " - Ideas-to-Tickets CLI Tool\n\n",
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
          tickets [subcommand]    Manage tickets (list, show, start, done, reset)
          path <session_id>       Print session path (use with cd)
          replan <session_path>   Re-run planning phase with different parameters
          config [subcommand]     Manage configuration (show, set-provider, set-key)

      """,
      Owl.Data.tag("OPTIONS:", :yellow),
      """

          -t, --task <desc>       Task description (required for analyze/plan)
          -n, --name <name>       Project name (required for plan)
          -S, --session <name>    Custom session name (optional)
          --stack <stack>         Tech stack: phoenix, rails, nextjs, fastapi, etc.
          --database <db>         Database: postgres, mysql, sqlite, mongodb
          -i, --interactive       Enable interactive clarifying questions
          -s, --scope <scope>     Planning scope: full (default), minimal
          -h, --help              Show this help message
          -v, --version           Show version

      """,
      Owl.Data.tag("EXAMPLES:", :yellow),
      """

          # Analyze existing codebase
          albedo analyze ~/projects/myapp --task "Add user authentication"
          albedo analyze . -t "Add auth" --session auth-feature

          # Plan new project from scratch
          albedo plan --name my_todo --task "Build a todo app with user accounts"
          albedo plan -n shop_api -t "E-commerce API" --stack phoenix -S shop-v1

          # Configuration management
          albedo config                    # Show current config
          albedo config set-provider       # Change LLM provider
          albedo config set-key            # Set API key

          # Session management
          albedo sessions
          albedo show auth-feature
          cd $(albedo path auth-feature)
          albedo resume ~/.albedo/sessions/auth-feature/

          # Ticket management
          albedo tickets                    # List tickets from latest session
          albedo tickets --session my-session
          albedo tickets --status pending   # Filter by status
          albedo tickets show 1             # Show ticket details
          albedo tickets start 1            # Start working on ticket
          albedo tickets done 1 2 3         # Mark tickets as completed
          albedo tickets reset --all        # Reset all tickets

          # Export tickets
          albedo tickets export                        # JSON to stdout
          albedo tickets export --format csv -o out.csv
          albedo tickets export --format markdown      # Markdown checklist
          albedo tickets export --format github        # GitHub Issues format

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
