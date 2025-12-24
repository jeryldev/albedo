defmodule Albedo.Agents.ImpactTracer do
  @moduledoc """
  Phase 3: Impact Analysis Agent.
  Traces all dependencies and determines what else will be affected by changes.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts
  alias Albedo.Search.Ripgrep

  @impl Albedo.Agents.Base
  def investigate(state) do
    path = state.codebase_path
    task = state.task
    previous_context = state.context

    feature_files = extract_feature_files(previous_context)
    dependency_info = trace_dependencies(path, feature_files)

    prompt =
      Prompts.impact_analysis(task, previous_context, format_dependency_info(dependency_info))

    case call_llm(prompt) do
      {:ok, response} ->
        findings = %{
          feature_files: feature_files,
          dependencies: dependency_info,
          content: response
        }

        {:ok, findings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Albedo.Agents.Base
  def format_output(findings) do
    findings.content
  end

  defp extract_feature_files(context) do
    feature_location = context[:feature_location] || %{}
    search_results = feature_location[:search_results] || %{}

    keyword_files =
      (search_results[:keyword_matches] || [])
      |> Enum.map(& &1.file)

    schema_files =
      (search_results[:schemas] || [])
      |> Enum.map(& &1.file)

    (keyword_files ++ schema_files)
    |> Enum.uniq()
    |> Enum.take(20)
  end

  defp trace_dependencies(path, files) do
    direct_deps = trace_direct_dependencies(path, files)
    indirect_deps = trace_indirect_dependencies(path, direct_deps)
    query_usages = find_query_usages(path, files)
    side_effects = find_side_effects(path, files)

    %{
      direct: direct_deps,
      indirect: indirect_deps,
      queries: query_usages,
      side_effects: side_effects
    }
  end

  defp trace_direct_dependencies(path, files) do
    files
    |> Enum.flat_map(fn file ->
      module_name = extract_module_name(file)

      if module_name do
        case Ripgrep.search("alias #{module_name}|import #{module_name}|use #{module_name}",
               path: path,
               type: "elixir"
             ) do
          {:ok, results} ->
            results
            |> Enum.reject(&(&1.file == file))
            |> Enum.map(fn result ->
              %{
                source_file: file,
                dependent_file: result.file,
                type: determine_dependency_type(result.matches)
              }
            end)

          _ ->
            []
        end
      else
        []
      end
    end)
    |> Enum.uniq_by(& &1.dependent_file)
  end

  defp trace_indirect_dependencies(path, direct_deps) do
    direct_files = Enum.map(direct_deps, & &1.dependent_file)

    direct_files
    |> Enum.flat_map(fn file ->
      module_name = extract_module_name(file)

      if module_name do
        case Ripgrep.search("#{module_name}\\.", path: path, type: "elixir", max_count: 5) do
          {:ok, results} ->
            results
            |> Enum.reject(&(&1.file in direct_files))
            |> Enum.map(fn result ->
              %{
                source_file: file,
                dependent_file: result.file,
                type: :indirect
              }
            end)

          _ ->
            []
        end
      else
        []
      end
    end)
    |> Enum.uniq_by(& &1.dependent_file)
    |> Enum.take(10)
  end

  defp find_query_usages(path, files) do
    field_names =
      files
      |> Enum.flat_map(fn file ->
        case File.read(file) do
          {:ok, content} ->
            Regex.scan(~r/field\s+:(\w+)/, content)
            |> Enum.map(fn [_, name] -> name end)

          _ ->
            []
        end
      end)
      |> Enum.uniq()

    field_names
    |> Enum.flat_map(fn field ->
      patterns = [
        "where.*:#{field}",
        "order_by.*:#{field}",
        "select.*:#{field}",
        "group_by.*:#{field}"
      ]

      patterns
      |> Enum.flat_map(fn pattern ->
        case Ripgrep.search(pattern, path: path, type: "elixir", max_count: 5) do
          {:ok, results} ->
            Enum.map(results, fn r ->
              %{field: field, file: r.file, pattern: pattern, matches: r.matches}
            end)

          _ ->
            []
        end
      end)
    end)
    |> Enum.take(15)
  end

  defp find_side_effects(path, _files) do
    notifications =
      case Ripgrep.search("Notifier|Mailer|send_email|deliver",
             path: path,
             type: "elixir",
             max_count: 10
           ) do
        {:ok, results} -> results
        _ -> []
      end

    workers =
      case Ripgrep.search("Oban.Worker|perform|enqueue",
             path: path,
             type: "elixir",
             max_count: 10
           ) do
        {:ok, results} -> results
        _ -> []
      end

    external_apis =
      case Ripgrep.search("Req\\.|HTTPoison|Tesla|webhook|api_call",
             path: path,
             type: "elixir",
             max_count: 10
           ) do
        {:ok, results} -> results
        _ -> []
      end

    %{
      notifications: notifications,
      workers: workers,
      external_apis: external_apis
    }
  end

  defp extract_module_name(file) do
    case File.read(file) do
      {:ok, content} ->
        case Regex.run(~r/defmodule\s+([\w.]+)/, content) do
          [_, module] -> module
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp determine_dependency_type(matches) do
    match_content = Enum.map_join(matches, " ", & &1.content)

    cond do
      String.contains?(match_content, "alias") -> :alias
      String.contains?(match_content, "import") -> :import
      String.contains?(match_content, "use") -> :use
      true -> :reference
    end
  end

  defp format_dependency_info(info) do
    sections = []

    sections =
      if info.direct != [] do
        direct_section =
          Enum.map_join(info.direct, "\n", fn dep ->
            "- #{dep.dependent_file} (#{dep.type}) → depends on #{dep.source_file}"
          end)

        sections ++ ["## Direct Dependencies\n#{direct_section}"]
      else
        sections ++ ["## Direct Dependencies\nNo direct dependencies found."]
      end

    sections =
      if info.indirect != [] do
        indirect_section =
          Enum.map_join(info.indirect, "\n", fn dep ->
            "- #{dep.dependent_file} → indirectly depends on #{dep.source_file}"
          end)

        sections ++ ["## Indirect Dependencies\n#{indirect_section}"]
      else
        sections
      end

    sections =
      if info.queries != [] do
        query_section =
          Enum.map_join(info.queries, "\n", fn q ->
            "- #{q.file}: query on :#{q.field}"
          end)

        sections ++ ["## Query Usages\n#{query_section}"]
      else
        sections
      end

    sections =
      sections ++
        [
          """
          ## Side Effects

          ### Notifications
          #{format_side_effect_results(info.side_effects.notifications)}

          ### Background Workers
          #{format_side_effect_results(info.side_effects.workers)}

          ### External APIs
          #{format_side_effect_results(info.side_effects.external_apis)}
          """
        ]

    Enum.join(sections, "\n\n")
  end

  defp format_side_effect_results([]), do: "None found."

  defp format_side_effect_results(results) do
    results
    |> Enum.take(5)
    |> Enum.map_join("\n", fn r -> "- #{r.file}" end)
  end
end
