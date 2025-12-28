defmodule Albedo.CLI.Commands.Projects do
  @moduledoc """
  CLI commands for managing Albedo projects.
  Handles list, create, rename, and delete operations.
  """

  alias Albedo.CLI.Output
  alias Albedo.{Config, Project}

  @spec dispatch(list(String.t()), keyword()) :: :ok | no_return()
  def dispatch([], opts) do
    if opts[:help], do: help(), else: list()
  end

  def dispatch(["help" | _], _opts), do: help()
  def dispatch(["list" | _], _opts), do: list()

  def dispatch(["create" | rest], opts) do
    task = opts[:task] || List.first(rest)
    create(task, opts)
  end

  def dispatch(["rename", project_id, new_name | _], _opts) do
    rename(project_id, new_name)
  end

  def dispatch(["rename", _project_id | _], _opts) do
    Output.print_error("Missing new name for project")
    Output.print_info("Usage: albedo projects rename <project_id> <new_name>")
    halt_with_error(1)
  end

  def dispatch(["rename" | _], _opts) do
    Output.print_error("Missing project ID and new name")
    Output.print_info("Usage: albedo projects rename <project_id> <new_name>")
    halt_with_error(1)
  end

  def dispatch(["delete", project_id | _], opts) do
    delete(project_id, opts)
  end

  def dispatch(["delete" | _], _opts) do
    Output.print_error("Missing project ID")
    Output.print_info("Usage: albedo projects delete <project_id> [--yes]")
    halt_with_error(1)
  end

  def dispatch([unknown | _], _opts) do
    Output.print_error("Unknown projects subcommand: #{unknown}")
    IO.puts("")
    help()
    halt_with_error(1)
  end

  def help do
    Owl.IO.puts([
      Owl.Data.tag("albedo projects", :cyan),
      " - Manage analysis projects\n\n",
      Owl.Data.tag("USAGE:", :yellow),
      "\n    albedo projects [subcommand] [options]\n\n",
      Owl.Data.tag("SUBCOMMANDS:", :yellow),
      """

          list                    List all projects (default)
          create                  Create a new project folder
          rename <id> <name>      Rename a project folder
          delete <id>             Delete a project folder
          help                    Show this help message

      """,
      Owl.Data.tag("OPTIONS:", :yellow),
      """

          --task <desc>           Task description (for create)
          --yes                   Skip confirmation (for delete)
          --help                  Show this help message

      """,
      Owl.Data.tag("EXAMPLES:", :yellow),
      """

          # List all projects
          albedo projects
          albedo projects list

          # Create a new project
          albedo projects create --task "Add user authentication"
          albedo projects create "Add auth feature"

          # Rename a project
          albedo projects rename 20250101-add-auth auth-v2

          # Delete a project
          albedo projects delete 20250101-add-auth
          albedo projects delete 20250101-add-auth --yes

      """,
      Owl.Data.tag("PROJECT STRUCTURE:", :yellow),
      """

          Each project is stored in ~/.albedo/projects/<project_id>/

          Project files:
            project.json      Project state and metadata
            tickets.json      Generated tickets
            FEATURE.md        Feature documentation output
            context/          Phase outputs (domain research, tech stack, etc.)
      """
    ])
  end

  defp list do
    Output.print_header()
    config = Config.load!()
    projects_dir = Config.projects_dir(config)

    case File.ls(projects_dir) do
      {:ok, []} ->
        Output.print_info("No projects found.")

      {:ok, projects} ->
        Output.print_info("Recent projects:")
        Output.print_separator()
        projects |> Enum.sort(:desc) |> Enum.each(&print_project_info(&1, projects_dir))

      {:error, :enoent} ->
        Output.print_info("No projects directory found. Run 'albedo init' first.")

      {:error, reason} ->
        Output.print_error("Failed to list projects: #{inspect(reason)}")
    end
  end

  defp create(nil, _opts) do
    Output.print_error("Missing task description")
    Output.print_info("Usage: albedo projects create --task \"Your task description\"")
    Output.print_info("   or: albedo projects create \"Your task description\"")
    halt_with_error(1)
  end

  defp create(task, opts) do
    Output.print_header()

    case Project.create_folder(task, opts) do
      {:ok, project_id, project_dir} ->
        Output.print_success("Created project: #{project_id}")
        Output.print_info("Project path: #{project_dir}")
        IO.puts("")
        IO.puts("Next steps:")
        IO.puts("  albedo show #{project_id}")
        IO.puts("  cd $(albedo path #{project_id})")

      {:error, reason} ->
        Output.print_error("Failed to create project: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp rename(project_id, new_name) do
    Output.print_header()

    case Project.rename_folder(project_id, new_name) do
      {:ok, new_id, new_dir} ->
        Output.print_success("Renamed project: #{project_id} -> #{new_id}")
        Output.print_info("New path: #{new_dir}")

      {:error, :project_not_found} ->
        Output.print_error("Project not found: #{project_id}")
        halt_with_error(1)

      {:error, :name_already_exists} ->
        Output.print_error("A project with that name already exists")
        halt_with_error(1)

      {:error, reason} ->
        Output.print_error("Failed to rename project: #{inspect(reason)}")
        halt_with_error(1)
    end
  end

  defp delete(project_id, opts) do
    Output.print_header()
    skip_confirm = opts[:yes] == true

    if skip_confirm or confirm_delete(project_id) do
      case Project.delete_folder(project_id) do
        :ok ->
          Output.print_success("Deleted project: #{project_id}")

        {:error, :project_not_found} ->
          Output.print_error("Project not found: #{project_id}")
          halt_with_error(1)

        {:error, reason} ->
          Output.print_error("Failed to delete project: #{inspect(reason)}")
          halt_with_error(1)
      end
    else
      Output.print_info("Cancelled")
    end
  end

  defp confirm_delete(project_id) do
    IO.puts("About to delete project: #{project_id}")
    IO.puts("This will remove all project files permanently.")
    IO.puts("")
    response = safe_gets("Are you sure? [y/N] ") |> String.downcase()
    response in ["y", "yes"]
  end

  defp print_project_info(project, projects_dir) do
    project_file = Path.join([projects_dir, project, "project.json"])
    {state, task} = load_project_metadata(project_file)
    Output.print_project(project, state, task)
  end

  defp load_project_metadata(project_file) do
    with true <- File.exists?(project_file),
         {:ok, content} <- File.read(project_file),
         {:ok, data} <- Jason.decode(content) do
      state = data["state"] || "unknown"
      task = String.slice(data["task"] || "No task", 0, 60)
      {state, task}
    else
      _ -> {"?", ""}
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

  defp safe_gets(prompt) do
    case IO.gets(prompt) do
      :eof -> ""
      {:error, _} -> ""
      result when is_binary(result) -> String.trim(result)
    end
  end
end
