defmodule Albedo.Agents.Architecture do
  @moduledoc """
  Phase 1b: Architecture Mapping Agent.
  Understands how the codebase is organized structurally.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts
  alias Albedo.Search.{FileScanner, Ripgrep}

  @max_tree_depth 4
  @max_routes 20
  @greenfield_max_tokens 8192

  @impl Albedo.Agents.Base
  def investigate(state) do
    context = state.context

    if context[:greenfield] do
      investigate_greenfield(state)
    else
      investigate_existing(state)
    end
  end

  defp investigate_greenfield(state) do
    task = state.task
    context = state.context

    prompt = Prompts.architecture(task, context)

    case call_llm(prompt, max_tokens: @greenfield_max_tokens) do
      {:ok, response} ->
        findings = %{
          greenfield: true,
          content: response
        }

        {:ok, findings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp investigate_existing(state) do
    path = state.codebase_path
    task = state.task
    previous_context = state.context

    with {:ok, tree} <- FileScanner.tree(path, max_depth: @max_tree_depth),
         {:ok, project_type} <- FileScanner.detect_project_type(path) do
      structure_info = analyze_structure(path, project_type)

      context =
        Map.merge(previous_context, %{
          structure: tree,
          structure_info: structure_info
        })

      prompt = Prompts.architecture(task, context)

      case call_llm(prompt) do
        {:ok, response} ->
          findings = %{
            project_type: project_type,
            structure: tree,
            contexts: structure_info[:contexts],
            entry_points: structure_info[:entry_points],
            content: response
          }

          {:ok, findings}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl Albedo.Agents.Base
  def format_output(findings) do
    findings.content
  end

  defp analyze_structure(path, project_type) do
    case project_type do
      :phoenix -> analyze_phoenix_structure(path)
      :elixir -> analyze_elixir_structure(path)
      :umbrella -> analyze_umbrella_structure(path)
      _ -> %{contexts: [], entry_points: []}
    end
  end

  defp analyze_phoenix_structure(path) do
    lib_path = Path.join(path, "lib")

    app_name =
      case File.ls(lib_path) do
        {:ok, entries} ->
          entries
          |> Enum.reject(&String.ends_with?(&1, "_web"))
          |> Enum.find(fn entry ->
            File.dir?(Path.join(lib_path, entry))
          end)

        _ ->
          nil
      end

    contexts =
      if app_name do
        app_path = Path.join(lib_path, app_name)
        find_contexts(app_path, app_name)
      else
        []
      end

    entry_points = find_entry_points(path, app_name)

    %{
      app_name: app_name,
      contexts: contexts,
      entry_points: entry_points
    }
  end

  defp analyze_elixir_structure(path) do
    lib_path = Path.join(path, "lib")

    modules =
      case FileScanner.find_files(lib_path, "*.ex") do
        {:ok, files} -> Enum.map(files, &Path.basename(&1, ".ex"))
        _ -> []
      end

    %{
      contexts: [],
      modules: modules,
      entry_points: []
    }
  end

  defp analyze_umbrella_structure(path) do
    apps_path = Path.join(path, "apps")

    apps =
      case File.ls(apps_path) do
        {:ok, entries} ->
          entries
          |> Enum.filter(fn entry ->
            File.dir?(Path.join(apps_path, entry))
          end)
          |> Enum.map(fn app ->
            app_path = Path.join(apps_path, app)
            %{name: app, contexts: find_contexts(Path.join([app_path, "lib", app]), app)}
          end)

        _ ->
          []
      end

    %{
      type: :umbrella,
      apps: apps,
      contexts: Enum.flat_map(apps, & &1.contexts),
      entry_points: []
    }
  end

  defp find_contexts(app_path, app_name) do
    case File.ls(app_path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn entry ->
          full_path = Path.join(app_path, entry)
          File.dir?(full_path)
        end)
        |> Enum.map(fn dir ->
          context_path = Path.join(app_path, dir)
          schemas = find_schemas(context_path)
          functions = find_context_functions(app_path, dir, app_name)

          %{
            name: dir,
            schemas: schemas,
            functions: functions
          }
        end)

      _ ->
        []
    end
  end

  defp find_schemas(context_path) do
    case Ripgrep.search("use.*Schema|use Ecto.Schema", path: context_path, type: "elixir") do
      {:ok, results} ->
        results
        |> Enum.map(& &1.file)
        |> Enum.map(&Path.basename(&1, ".ex"))
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp find_context_functions(app_path, context_name, _app_name) do
    context_file = Path.join(app_path, "#{context_name}.ex")
    extract_function_names(context_file)
  end

  defp extract_function_names(file_path) do
    with true <- File.exists?(file_path),
         {:ok, content} <- File.read(file_path) do
      Regex.scan(~r/def\s+(\w+)\s*\(/, content)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.uniq()
    else
      _ -> []
    end
  end

  defp find_entry_points(path, app_name) do
    []
    |> maybe_add_routes(path, app_name)
    |> maybe_add_workers(path, app_name)
  end

  defp maybe_add_routes(entry_points, path, app_name) do
    router_path = Path.join([path, "lib", "#{app_name}_web", "router.ex"])

    case extract_routes(router_path) do
      [] -> entry_points
      routes -> entry_points ++ [{:router, routes}]
    end
  end

  defp extract_routes(router_path) do
    with true <- File.exists?(router_path),
         {:ok, content} <- File.read(router_path) do
      Regex.scan(~r/(get|post|put|patch|delete|live)\s+["']([^"']+)["']/, content)
      |> Enum.map(fn [_, method, route_path] -> {method, route_path} end)
      |> Enum.take(@max_routes)
    else
      _ -> []
    end
  end

  defp maybe_add_workers(entry_points, path, app_name) do
    workers_path = Path.join([path, "lib", app_name || "", "workers"])

    case extract_workers(workers_path) do
      [] -> entry_points
      workers -> entry_points ++ [{:workers, workers}]
    end
  end

  defp extract_workers(workers_path) do
    with true <- File.dir?(workers_path),
         {:ok, files} <- File.ls(workers_path) do
      Enum.filter(files, &String.ends_with?(&1, ".ex"))
    else
      _ -> []
    end
  end
end
