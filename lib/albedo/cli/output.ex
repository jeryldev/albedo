defmodule Albedo.CLI.Output do
  @moduledoc """
  Output formatting and printing functions for the Albedo CLI.
  All print_* and format_* helpers are centralized here.
  """

  @version Mix.Project.config()[:version]

  # =============================================================================
  # Core Output Functions
  # =============================================================================

  def print_header do
    Owl.IO.puts([
      Owl.Data.tag("Albedo", :cyan),
      " ",
      Owl.Data.tag("v#{@version}", :light_black),
      "\n",
      String.duplicate("━", 50),
      "\n"
    ])
  end

  def print_separator do
    IO.puts(String.duplicate("─", 50))
  end

  def print_info(message) do
    Owl.IO.puts(Owl.Data.tag(message, :light_black))
  end

  def print_success(message) do
    Owl.IO.puts(Owl.Data.tag("✓ #{message}", :green))
  end

  def print_error(message) do
    Owl.IO.puts(Owl.Data.tag("✗ #{message}", :red))
  end

  def print_warning(message) do
    Owl.IO.puts(Owl.Data.tag("⚠ #{message}", :yellow))
  end

  def print_version do
    IO.puts("Albedo v#{@version}")
  end

  def print_invalid_args(invalid) do
    Enum.each(invalid, fn {arg, _} ->
      print_error("Invalid option: #{arg}")
    end)
  end

  # =============================================================================
  # Help Output
  # =============================================================================

  def print_help do
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
          resume <project_path>   Resume an incomplete project
          projects [subcommand]   Manage projects (list, create, rename, delete)
          show <project_id>       View a project's output
          tickets [subcommand]    Manage tickets (list, show, start, done, reset)
          tui                     Interactive terminal UI (use 'albedo-tui' command)
          path <project_id>       Print project path (use with cd)
          replan <project_path>   Re-run planning phase with different parameters
          config [subcommand]     Manage configuration (show, set-provider, set-key)

      """,
      Owl.Data.tag("OPTIONS:", :yellow),
      """

          --task <desc>           Task description (required for analyze/plan)
          --name <name>           Project name (required for plan)
          --project <name>        Custom project name (optional)
          --stack <stack>         Tech stack: phoenix, rails, nextjs, fastapi, etc.
          --database <db>         Database: postgres, mysql, sqlite, mongodb
          --interactive           Enable interactive clarifying questions
          --scope <scope>         Planning scope: full (default), minimal
          --help                  Show this help message
          --version               Show version

      """,
      Owl.Data.tag("EXAMPLES:", :yellow),
      """

          # Analyze existing codebase
          albedo analyze ~/projects/myapp --task "Add user authentication"
          albedo analyze . --task "Add auth" --project auth-feature

          # Plan new project from scratch
          albedo plan --name my_todo --task "Build a todo app with user accounts"
          albedo plan --name shop_api --task "E-commerce API" --stack phoenix

          # Configuration management
          albedo config                    # Show current config
          albedo config set-provider       # Change LLM provider
          albedo config set-key            # Set API key

          # Project management
          albedo projects                      # List all projects
          albedo projects create "Add auth"   # Create new project folder
          albedo projects rename old-id new   # Rename project folder
          albedo projects delete old-id       # Delete project folder
          albedo show auth-feature
          cd $(albedo path auth-feature)
          albedo resume ~/.albedo/projects/auth-feature/

          # Ticket management
          albedo tickets                    # List tickets from latest project
          albedo tickets --project my-project
          albedo tickets --status pending   # Filter by status
          albedo tickets show 1             # Show ticket details
          albedo tickets start 1            # Start working on ticket
          albedo tickets done 1 2 3         # Mark tickets as completed
          albedo tickets reset --all        # Reset all tickets
          albedo tickets edit 1 --priority high --points 5

          # Export tickets
          albedo tickets export                        # JSON to stdout
          albedo tickets export --format csv --output out.csv
          albedo tickets export --format markdown      # Markdown checklist
          albedo tickets export --format github        # GitHub Issues format

      """,
      Owl.Data.tag("CONFIGURATION:", :yellow),
      """

          Config file: ~/.albedo/config.toml
          Projects:    ~/.albedo/projects/
      """
    ])
  end

  # =============================================================================
  # Project Output
  # =============================================================================

  def print_project(id, state, task) do
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

  def print_project_info(project, projects_dir) do
    print_header()

    IO.puts("Project: #{project.id}")
    IO.puts("Task: #{project.task || "No task description"}")
    IO.puts("State: #{project.state}")
    IO.puts("")

    if project.phases and project.phases != [] do
      IO.puts("Completed Phases:")

      Enum.each(project.phases, fn phase ->
        IO.puts("  ✓ #{phase}")
      end)

      IO.puts("")
    end

    feature_path = Path.join([projects_dir, project.id, "FEATURE.md"])

    if File.exists?(feature_path) do
      print_success("Feature plan available")
      IO.puts("  View: albedo show #{project.id}")
      IO.puts("  Path: #{feature_path}")
    else
      print_info("No feature plan yet")
    end
  end

  # =============================================================================
  # Summary Output
  # =============================================================================

  def print_summary(result) do
    IO.puts("")
    Owl.IO.puts(Owl.Data.tag("Summary:", :cyan))

    if result[:tickets_count] do
      IO.puts("  • #{result.tickets_count} tickets generated")
    end

    if result[:total_points] do
      IO.puts("  • #{result.total_points} story points estimated")
    end

    if result[:files_to_create] and result[:files_to_create] > 0 do
      IO.puts("  • #{result.files_to_create} files to create")
    end

    if result[:files_to_modify] and result[:files_to_modify] > 0 do
      IO.puts("  • #{result.files_to_modify} files to modify")
    end

    if result[:risks_identified] and result[:risks_identified] > 0 do
      IO.puts("  • #{result.risks_identified} risks identified")
    end

    print_next_steps(result)
  end

  def print_greenfield_summary(result) do
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

    if result[:setup_steps] and result[:setup_steps] > 0 do
      IO.puts("  • #{result.setup_steps} setup steps")
    end

    print_next_steps(result)
  end

  def print_next_steps(result) do
    IO.puts("")
    Owl.IO.puts(Owl.Data.tag("Next Steps:", :cyan))
    IO.puts("  1. View the plan:        albedo show #{result.project_id}")
    IO.puts("  2. Manage tickets:       albedo tickets --project #{result.project_id}")
    IO.puts("  3. Go to project folder: cd $(albedo path #{result.project_id})")
  end

  # =============================================================================
  # Ticket Output
  # =============================================================================

  def print_ticket_list(data, tickets) do
    IO.puts("Project: #{data.project_id}")
    IO.puts("Task: #{String.slice(data.task_description || "", 0, 60)}")
    print_separator()
    IO.puts("")

    IO.puts("  #  Status       Priority  Pts  Title")
    IO.puts("  ─  ──────       ────────  ───  ─────")

    Enum.each(tickets, fn ticket ->
      status_symbol = status_symbol(ticket.status)
      status_str = ticket.status |> to_string() |> String.pad_trailing(10)
      priority_str = ticket.priority |> to_string() |> String.pad_trailing(8)

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
        " ",
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
    IO.puts("  albedo tickets show 1                   # View ticket details")
    IO.puts("  albedo tickets start 1                  # Start working on ticket")
    IO.puts("  albedo tickets done 1                   # Mark ticket complete")
    IO.puts("  albedo tickets edit 1 --priority high   # Change priority")
    IO.puts("  albedo tickets edit 1 --points 5        # Change story points")
  end

  def print_ticket_detail(ticket) do
    print_ticket_header(ticket)
    print_ticket_status(ticket)
    print_ticket_metadata(ticket)
    print_ticket_sections(ticket)
    print_ticket_dependencies(ticket)
  end

  def print_add_success(ticket) do
    print_success("Ticket ##{ticket.id} created: #{ticket.title}")

    details =
      [
        if(ticket.priority != :medium, do: "priority=#{ticket.priority}"),
        if(ticket.estimate, do: "points=#{ticket.estimate}"),
        if(ticket.type != :feature, do: "type=#{ticket.type}"),
        if(ticket.labels != [], do: "labels=#{Enum.join(ticket.labels, ",")}")
      ]
      |> Enum.reject(&is_nil/1)

    if details != [], do: IO.puts("  #{Enum.join(details, ", ")}")
  end

  def print_edit_usage do
    print_error("No changes specified")

    IO.puts(~S"""

    Usage:
      albedo tickets edit <id> --title "New title"
      albedo tickets edit <id> --description "New description"
      albedo tickets edit <id> --priority high --points 5
      albedo tickets edit <id> --status in_progress
      albedo tickets edit <id> --type bugfix --labels "tag1,tag2"

    Options:
      --title           Update ticket title
      --description     Update ticket description
      --priority        Priority: urgent, high, medium, low, none
      --points          Story points (1, 2, 3, 5, 8, 13)
      --status          Status: pending, in_progress, completed
      --type            Type: feature, bugfix, chore, docs, test
      --labels          Comma-separated labels
    """)
  end

  def print_edit_success(id, ticket, changes) do
    changes_str =
      [
        if(changes[:title], do: "title=\"#{ticket.title}\""),
        if(changes[:description], do: "description updated"),
        if(changes[:priority], do: "priority=#{ticket.priority}"),
        if(changes[:points], do: "points=#{ticket.estimate}"),
        if(changes[:status], do: "status=#{ticket.status}"),
        if(changes[:type], do: "type=#{ticket.type}"),
        if(changes[:labels], do: "labels=#{Enum.join(ticket.labels, ",")}")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    print_success("Ticket ##{id} updated: #{changes_str}")
  end

  # =============================================================================
  # Ticket Output Helpers (Private)
  # =============================================================================

  defp print_ticket_header(ticket) do
    Owl.IO.puts([
      "Ticket #",
      Owl.Data.tag(ticket.id, :cyan),
      ": ",
      ticket.title
    ])

    print_separator()
    IO.puts("")
  end

  defp print_ticket_status(ticket) do
    color = status_color(ticket.status)

    Owl.IO.puts([
      "Status:     ",
      Owl.Data.tag("#{status_symbol(ticket.status)} #{ticket.status}", color)
    ])
  end

  defp print_ticket_metadata(ticket) do
    IO.puts("Type:       #{ticket.type}")
    IO.puts("Priority:   #{ticket.priority}")
    print_optional_field("Estimate", ticket.estimate, &"#{&1} points")
    print_optional_list("Labels", ticket.labels, &Enum.join(&1, ", "))
    IO.puts("")
  end

  defp print_ticket_sections(ticket) do
    print_optional_section("Description", ticket.description, &IO.puts("  #{&1}"))
    print_file_section("Files to Create", ticket.files.create)
    print_file_section("Files to Modify", ticket.files.modify)
    print_acceptance_criteria(ticket.acceptance_criteria)
  end

  defp print_ticket_dependencies(ticket) do
    print_optional_list_inline("Blocked by", ticket.dependencies.blocked_by, "#")
    print_optional_list_inline("Blocks", ticket.dependencies.blocks, "#")
  end

  defp print_optional_field(_label, nil, _formatter), do: :ok

  defp print_optional_field(label, value, formatter),
    do: IO.puts("#{label}:   #{formatter.(value)}")

  defp print_optional_list(_label, [], _formatter), do: :ok

  defp print_optional_list(label, list, formatter),
    do: IO.puts("#{label}:     #{formatter.(list)}")

  defp print_optional_section(_title, nil, _printer), do: :ok

  defp print_optional_section(title, content, printer) do
    Owl.IO.puts(Owl.Data.tag("#{title}:", :cyan))
    printer.(content)
    IO.puts("")
  end

  defp print_file_section(_title, []), do: :ok

  defp print_file_section(title, files) do
    Owl.IO.puts(Owl.Data.tag("#{title}:", :cyan))
    Enum.each(files, &IO.puts("  • #{&1}"))
    IO.puts("")
  end

  defp print_acceptance_criteria([]), do: :ok

  defp print_acceptance_criteria(criteria) do
    Owl.IO.puts(Owl.Data.tag("Acceptance Criteria:", :cyan))

    Enum.each(criteria, fn criterion ->
      clean = String.replace(criterion, ~r/^\s*\[[ x~]\]\s*/, "")
      IO.puts("  ☐ #{clean}")
    end)

    IO.puts("")
  end

  defp print_optional_list_inline(_label, [], _prefix), do: :ok

  defp print_optional_list_inline(label, items, prefix) do
    IO.puts("#{label}: #{prefix}#{Enum.join(items, ", #{prefix}")}")
  end

  # =============================================================================
  # Status Helpers
  # =============================================================================

  def status_symbol(:pending), do: "○"
  def status_symbol(:in_progress), do: "●"
  def status_symbol(:completed), do: "✓"

  def status_color(:completed), do: :green
  def status_color(:in_progress), do: :yellow
  def status_color(:pending), do: :light_black

  # =============================================================================
  # Shell/Config Output
  # =============================================================================

  def print_shell_update_success(action, env_var, shell_profile) do
    action_verb = if action == :replaced, do: "Updated", else: "Added"
    print_success("#{action_verb} #{env_var} in #{shell_profile}")
    print_info("Run: source #{shell_profile}")
  end

  def check_ripgrep do
    case System.find_executable("rg") do
      nil ->
        print_warning("ripgrep (rg) not found")
        IO.puts("")
        print_info("ripgrep is required for codebase analysis.")
        IO.puts("")
        IO.puts("Install it:")

        case :os.type() do
          {:unix, :darwin} ->
            IO.puts("  brew install ripgrep")

          {:unix, _} ->
            IO.puts("  # Ubuntu/Debian:")
            IO.puts("  sudo apt-get install ripgrep")
            IO.puts("")
            IO.puts("  # Fedora:")
            IO.puts("  sudo dnf install ripgrep")

          _ ->
            IO.puts("  See: https://github.com/BurntSushi/ripgrep#installation")
        end

        IO.puts("")
        :missing

      _path ->
        {version, 0} = System.cmd("rg", ["--version"])
        version_line = version |> String.split("\n") |> List.first()
        print_success("ripgrep found: #{version_line}")
        :ok
    end
  end

  # =============================================================================
  # Utility Functions
  # =============================================================================

  def mask_api_key(key) when is_binary(key) and byte_size(key) > 12 do
    "#{String.slice(key, 0, 8)}...#{String.slice(key, -4, 4)}"
  end

  def mask_api_key(key) when is_binary(key), do: "****"
  def mask_api_key(_), do: "NOT SET"

  def format_error(:rate_limited) do
    "API rate limit exceeded. Wait a minute and try again."
  end

  def format_error(:invalid_api_key) do
    "Invalid API key. Run 'albedo config set-key' to set your API key."
  end

  def format_error(:max_retries_exceeded),
    do: "Request failed after retries. Check your network connection."

  def format_error(:timeout), do: "Request timed out. Check your network connection."
  def format_error({:http_error, status}), do: "HTTP error: #{status}"
  def format_error(reason), do: inspect(reason)
end
