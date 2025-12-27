defmodule Albedo.CLI.Commands.Tickets do
  @moduledoc """
  CLI commands for ticket management.
  Handles list, show, add, edit, delete, start, done, reset, and export operations.
  """

  alias Albedo.CLI.Output
  alias Albedo.{Config, Tickets}
  alias Albedo.Tickets.Exporter

  def dispatch([], opts) do
    if opts[:help], do: help(), else: dispatch(["list"], opts)
  end

  def dispatch(["help" | _], _opts), do: help()

  def dispatch(["list" | _], opts) do
    Output.print_header()
    project_dir = resolve_project_dir(opts)

    case Tickets.load(project_dir) do
      {:ok, data} ->
        tickets = Tickets.list(data, Keyword.take(opts, [:status]))
        Output.print_ticket_list(data, tickets)

      {:error, :not_found} ->
        Output.print_error("No tickets.json found for this project")
        Output.print_info("Run 'albedo analyze' first to generate tickets")
        halt_with_error(1)

      {:error, reason} ->
        Output.print_error("Failed to load tickets: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  def dispatch(["show", id | _], opts) do
    Output.print_header()
    project_dir = resolve_project_dir(opts)

    with {:ok, data} <- load_tickets_data(project_dir),
         {:ok, ticket} <- fetch_ticket(data, id) do
      display_ticket(ticket, opts)
    end
  end

  def dispatch(["start", id | _], opts) do
    update_ticket_status(id, :start, opts)
  end

  def dispatch(["done" | ids], opts) do
    Enum.each(ids, fn id ->
      update_ticket_status(id, :complete, opts)
    end)
  end

  def dispatch(["reset" | ids], opts) do
    if opts[:all] do
      reset_all_tickets(opts)
    else
      Enum.each(ids, fn id ->
        update_ticket_status(id, :reset, opts)
      end)
    end
  end

  def dispatch(["add" | rest], opts) do
    title = opts[:title] || List.first(rest)
    add_ticket(title, opts)
  end

  def dispatch(["delete" | ids], opts) do
    delete_tickets(ids, opts)
  end

  def dispatch(["edit", id | _], opts) do
    edit_ticket(id, opts)
  end

  def dispatch(["export" | _], opts) do
    export_tickets(opts)
  end

  def dispatch([unknown | _], _opts) do
    Output.print_error("Unknown tickets subcommand: #{unknown}")
    IO.puts("")
    help()
    halt_with_error(1)
  end

  def help do
    Owl.IO.puts([
      Owl.Data.tag("albedo tickets", :cyan),
      " - Manage implementation tickets\n\n",
      Owl.Data.tag("USAGE:", :yellow),
      "\n    albedo tickets [subcommand] [options]\n\n",
      Owl.Data.tag("SUBCOMMANDS:", :yellow),
      """

          list                    List all tickets (default)
          show <id>               Show ticket details
          add <title>             Add a new ticket
          edit <id>               Edit ticket properties
          delete <id> [ids...]    Delete ticket(s)
          start <id>              Mark ticket as in-progress
          done <id> [ids...]      Mark ticket(s) as completed
          reset <id> [ids...]     Reset ticket(s) to pending
          export                  Export tickets to various formats
          help                    Show this help message

      """,
      Owl.Data.tag("OPTIONS:", :yellow),
      """

          -P, --project <id>      Target a specific project (default: latest)
          --status <status>       Filter by status: pending, in_progress, completed
          --json                  Output in JSON format (for show)
          -y, --yes               Skip confirmation (for delete)
          -h, --help              Show this help message

      """,
      Owl.Data.tag("ADD OPTIONS:", :yellow),
      """

          -t, --title <title>     Ticket title (required)
          -d, --description <d>   Ticket description
          -p, --priority <p>      Priority: urgent, high, medium (default), low, none
          --points <n>            Story points: 1, 2, 3, 5, 8, 13
          --type <type>           Type: feature (default), bugfix, chore, docs, test
          --labels <labels>       Comma-separated labels

      """,
      Owl.Data.tag("EDIT OPTIONS:", :yellow),
      """

          --title <title>         Update title
          --description <d>       Update description
          --priority <p>          Update priority
          --points <n>            Update story points
          --status <status>       Update status
          --type <type>           Update type
          --labels <labels>       Update labels

      """,
      Owl.Data.tag("EXPORT OPTIONS:", :yellow),
      """

          -f, --format <fmt>      Format: json (default), csv, markdown, github
          -o, --output <file>     Output file (default: stdout)
          --status <status>       Filter by status

      """,
      Owl.Data.tag("EXAMPLES:", :yellow),
      """

          # List tickets
          albedo tickets                         # From latest project
          albedo tickets --project auth-feature  # From specific project
          albedo tickets --status pending        # Filter by status

          # Show ticket details
          albedo tickets show 1
          albedo tickets show 1 --json

          # Add tickets
          albedo tickets add "Implement login"
          albedo tickets add "Fix bug" --type bugfix --priority high
          albedo tickets add "Add tests" --points 3 --labels "testing,backend"

          # Update status
          albedo tickets start 1
          albedo tickets done 1 2 3
          albedo tickets reset 1
          albedo tickets reset --all

          # Edit tickets
          albedo tickets edit 1 --title "New title"
          albedo tickets edit 1 --priority high --points 5

          # Delete tickets
          albedo tickets delete 1
          albedo tickets delete 1 2 3 --yes

          # Export
          albedo tickets export
          albedo tickets export --format csv -o tickets.csv
          albedo tickets export --format markdown
          albedo tickets export --format github --status pending

      """,
      Owl.Data.tag("TICKET STATUSES:", :yellow),
      """

          pending       Not started (default)
          in_progress   Currently being worked on
          completed     Finished

      """,
      Owl.Data.tag("TICKET TYPES:", :yellow),
      """

          feature       New functionality (default)
          bugfix        Bug fix
          chore         Maintenance/housekeeping
          docs          Documentation
          test          Testing
      """
    ])
  end

  # =============================================================================
  # Display Helpers
  # =============================================================================

  defp display_ticket(ticket, opts) do
    if opts[:json] do
      ticket |> Tickets.Ticket.to_json() |> Jason.encode!(pretty: true) |> IO.puts()
    else
      Output.print_ticket_detail(ticket)
    end
  end

  # =============================================================================
  # Status Update Operations
  # =============================================================================

  defp update_ticket_status(id, action, opts) do
    project_dir = resolve_project_dir(opts)

    with {:ok, data} <- load_tickets_data(project_dir),
         {:ok, updated_data, ticket} <- apply_ticket_action(data, id, action),
         :ok <- save_tickets_data(project_dir, updated_data) do
      Output.print_success("Ticket ##{id} #{action_label(action)}: #{ticket.title}")
    end
  end

  defp reset_all_tickets(opts) do
    project_dir = resolve_project_dir(opts)

    with {:ok, data} <- load_tickets_data(project_dir),
         :ok <- save_tickets_data(project_dir, Tickets.reset_all(data)) do
      Output.print_success("All tickets reset to pending")
    end
  end

  defp apply_ticket_action(data, id, action) do
    action_fn = get_action_fn(action)

    case action_fn.(data, id) do
      {:ok, _, _} = result ->
        result

      {:error, :not_found} ->
        Output.print_error("Ticket ##{id} not found")
        halt_with_error(1)
    end
  end

  defp get_action_fn(:start), do: &Tickets.start/2
  defp get_action_fn(:complete), do: &Tickets.complete/2
  defp get_action_fn(:reset), do: &Tickets.reset/2

  defp action_label(:start), do: "started"
  defp action_label(:complete), do: "completed"
  defp action_label(:reset), do: "reset"

  # =============================================================================
  # Add Ticket
  # =============================================================================

  defp add_ticket(nil, _opts) do
    Output.print_error("Title is required")

    IO.puts(~S"""

    Usage:
      albedo tickets add "Title here"
      albedo tickets add --title "Title here"
      albedo tickets add "Title" --description "Details" --priority high --points 5
      albedo tickets add "Title" --type bugfix --labels "backend,urgent"

    Options:
      --title, -t       Ticket title (required)
      --description, -d Ticket description
      --priority, -p    Priority: urgent, high, medium (default), low, none
      --points          Story points (1, 2, 3, 5, 8, 13)
      --type            Type: feature (default), bugfix, chore, docs, test
      --labels          Comma-separated labels
    """)

    halt_with_error(1)
  end

  defp add_ticket(title, opts) do
    project_dir = resolve_project_dir(opts)

    attrs = %{
      title: title,
      description: opts[:description],
      priority: opts[:priority],
      estimate: opts[:points],
      type: opts[:type],
      labels: opts[:labels]
    }

    {:ok, data} = load_tickets_or_error(project_dir)
    {:ok, updated_data, ticket} = Tickets.add(data, attrs)
    :ok = save_tickets_or_error(project_dir, updated_data)
    Output.print_add_success(ticket)
  end

  # =============================================================================
  # Delete Tickets
  # =============================================================================

  defp delete_tickets([], _opts) do
    Output.print_error("No ticket ID specified")

    IO.puts("""

    Usage:
      albedo tickets delete <id>            Delete a ticket (with confirmation)
      albedo tickets delete <id> --yes      Delete without confirmation
      albedo tickets delete 1 2 3           Delete multiple tickets
    """)

    halt_with_error(1)
  end

  defp delete_tickets(ids, opts) do
    project_dir = resolve_project_dir(opts)
    skip_confirm = opts[:yes] == true

    {:ok, data} = load_tickets_or_error(project_dir)
    tickets_to_delete = find_tickets_to_delete(data, ids)
    validate_tickets_found(tickets_to_delete)

    if confirm_deletion(tickets_to_delete, skip_confirm) do
      execute_deletion(data, ids, project_dir)
    else
      IO.puts("Cancelled")
    end
  end

  defp find_tickets_to_delete(data, ids) do
    ids
    |> Enum.map(&Tickets.get(data, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp validate_tickets_found([]) do
    Output.print_error("No matching tickets found")
    halt_with_error(1)
  end

  defp validate_tickets_found(_tickets), do: :ok

  defp confirm_deletion(_tickets, true), do: true

  defp confirm_deletion(tickets, false) do
    IO.puts("About to delete #{length(tickets)} ticket(s):")
    Enum.each(tickets, fn t -> IO.puts("  ##{t.id}: #{t.title}") end)
    IO.puts("")
    response = safe_gets("Are you sure? [y/N] ") |> String.downcase()
    response in ["y", "yes"]
  end

  defp execute_deletion(data, ids, project_dir) do
    {final_data, deleted_count} =
      Enum.reduce(ids, {data, 0}, fn id, {acc_data, count} ->
        case Tickets.delete(acc_data, id) do
          {:ok, updated_data, _ticket} -> {updated_data, count + 1}
          {:error, :not_found} -> {acc_data, count}
        end
      end)

    :ok = save_tickets_or_error(project_dir, final_data)
    Output.print_success("Deleted #{deleted_count} ticket(s)")
  end

  # =============================================================================
  # Edit Ticket
  # =============================================================================

  defp edit_ticket(id, opts) do
    changes = build_edit_changes(opts)

    if changes == %{} do
      Output.print_edit_usage()
      halt_with_error(1)
    end

    project_dir = resolve_project_dir(opts)
    {:ok, data} = load_tickets_or_error(project_dir)

    case Tickets.edit(data, id, changes) do
      {:ok, updated_data, ticket} ->
        :ok = save_tickets_or_error(project_dir, updated_data)
        Output.print_edit_success(id, ticket, changes)

      {:error, :not_found} ->
        Output.print_error("Ticket ##{id} not found")
        halt_with_error(1)
    end
  end

  defp build_edit_changes(opts) do
    %{
      title: opts[:title],
      description: opts[:description],
      priority: opts[:priority],
      points: opts[:points],
      status: opts[:status],
      type: opts[:type],
      labels: opts[:labels]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # =============================================================================
  # Export Tickets
  # =============================================================================

  defp export_tickets(opts) do
    Output.print_header()
    project_dir = resolve_project_dir(opts)

    with {:ok, format} <- parse_export_format(opts[:format] || "json"),
         {:ok, data} <- load_tickets_data(project_dir),
         {:ok, content} <- do_export(data, format, opts) do
      write_export_output(content, data, format, opts[:output])
    end
  end

  defp parse_export_format("json"), do: {:ok, :json}
  defp parse_export_format("csv"), do: {:ok, :csv}
  defp parse_export_format("markdown"), do: {:ok, :markdown}
  defp parse_export_format("md"), do: {:ok, :markdown}
  defp parse_export_format("github"), do: {:ok, :github}

  defp parse_export_format(other) do
    Output.print_error("Unknown format: #{other}")
    Output.print_info("Available formats: json, csv, markdown, github")
    halt_with_error(1)
  end

  defp do_export(data, format, opts) do
    export_opts = if opts[:status], do: [status: String.to_existing_atom(opts[:status])], else: []

    case Exporter.export(data, format, export_opts) do
      {:ok, content} ->
        {:ok, content}

      {:error, reason} ->
        Output.print_error("Export failed: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp write_export_output(content, _data, _format, nil) do
    IO.puts(content)
  end

  defp write_export_output(content, data, format, output_path) do
    case File.write(output_path, content) do
      :ok ->
        Output.print_success("Exported #{length(data.tickets)} tickets to #{output_path}")
        Output.print_info("Format: #{Exporter.format_name(format)}")

      {:error, reason} ->
        Output.print_error("Failed to write file: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  # =============================================================================
  # Data Loading/Saving Helpers
  # =============================================================================

  defp load_tickets_data(project_dir) do
    case Tickets.load(project_dir) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        Output.print_error("No tickets.json found for this project")
        halt_with_error(1)

      {:error, reason} ->
        Output.print_error("Failed to load tickets: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp fetch_ticket(data, id) do
    case Tickets.get(data, id) do
      nil ->
        Output.print_error("Ticket ##{id} not found")
        halt_with_error(1)

      ticket ->
        {:ok, ticket}
    end
  end

  defp save_tickets_data(project_dir, data) do
    case Tickets.save(project_dir, data) do
      :ok ->
        :ok

      {:error, reason} ->
        Output.print_error("Failed to save: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp load_tickets_or_error(project_dir) do
    case Tickets.load(project_dir) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        Output.print_error("No tickets.json found for this project")
        Output.print_info("Run 'albedo analyze' first to generate tickets")
        halt_with_error(1)

      {:error, reason} ->
        Output.print_error("Failed to load tickets: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp save_tickets_or_error(project_dir, data) do
    case Tickets.save(project_dir, data) do
      :ok ->
        :ok

      {:error, reason} ->
        Output.print_error("Failed to save: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  # =============================================================================
  # Shared Helpers
  # =============================================================================

  defp resolve_project_dir(opts) do
    case opts[:project] do
      nil ->
        config = Config.load!()
        projects_dir = Config.projects_dir(config)

        case File.ls(projects_dir) do
          {:ok, projects} when projects != [] ->
            most_recent = projects |> Enum.sort(:desc) |> List.first()
            Path.join(projects_dir, most_recent)

          _ ->
            Output.print_error("No projects found")
            halt_with_error(1)
        end

      project_id ->
        config = Config.load!()
        Path.join(Config.projects_dir(config), project_id)
    end
  end

  defp safe_gets(prompt) do
    case IO.gets(prompt) do
      :eof -> ""
      {:error, _} -> ""
      result when is_binary(result) -> String.trim(result)
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
