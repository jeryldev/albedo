defmodule Albedo.Agents.ImpactTracer do
  @moduledoc """
  Phase 3: Impact Analysis Agent.
  Traces all dependencies and determines what else will be affected by changes.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts
  alias Albedo.Search.Ripgrep

  @max_feature_files 20
  @max_indirect_deps 10
  @max_query_usages 15
  @max_side_effects 10
  @max_displayed_side_effects 5

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
  def format_output(findings), do: findings.content

  defp extract_feature_files(context) do
    search_results = get_in(context, [:feature_location, :search_results]) || %{}

    keyword_files = extract_files_from(search_results[:keyword_matches])
    schema_files = extract_files_from(search_results[:schemas])

    (keyword_files ++ schema_files)
    |> Enum.uniq()
    |> Enum.take(@max_feature_files)
  end

  defp extract_files_from(nil), do: []
  defp extract_files_from(results), do: Enum.map(results, & &1.file)

  defp trace_dependencies(path, files) do
    direct_deps = trace_direct_dependencies(path, files)
    indirect_deps = trace_indirect_dependencies(path, direct_deps)
    query_usages = find_query_usages(path, files)
    side_effects = find_side_effects(path)

    %{
      direct: direct_deps,
      indirect: indirect_deps,
      queries: query_usages,
      side_effects: side_effects
    }
  end

  defp trace_direct_dependencies(path, files) do
    files
    |> Enum.flat_map(&find_direct_deps_for_file(path, &1))
    |> Enum.uniq_by(& &1.dependent_file)
  end

  defp find_direct_deps_for_file(path, file) do
    case extract_module_name(file) do
      nil ->
        []

      module_name ->
        pattern = "alias #{module_name}|import #{module_name}|use #{module_name}"

        path
        |> search_elixir_files(pattern)
        |> Enum.reject(&(&1.file == file))
        |> Enum.map(&build_direct_dependency(file, &1))
    end
  end

  defp build_direct_dependency(source_file, result) do
    %{
      source_file: source_file,
      dependent_file: result.file,
      type: determine_dependency_type(result.matches)
    }
  end

  defp trace_indirect_dependencies(path, direct_deps) do
    direct_files = Enum.map(direct_deps, & &1.dependent_file)

    direct_files
    |> Enum.flat_map(&find_indirect_deps_for_file(path, &1, direct_files))
    |> Enum.uniq_by(& &1.dependent_file)
    |> Enum.take(@max_indirect_deps)
  end

  defp find_indirect_deps_for_file(path, file, exclude_files) do
    case extract_module_name(file) do
      nil ->
        []

      module_name ->
        path
        |> search_elixir_files("#{module_name}\\.", max_count: 5)
        |> Enum.reject(&(&1.file in exclude_files))
        |> Enum.map(&build_indirect_dependency(file, &1))
    end
  end

  defp build_indirect_dependency(source_file, result) do
    %{
      source_file: source_file,
      dependent_file: result.file,
      type: :indirect
    }
  end

  defp find_query_usages(path, files) do
    files
    |> extract_field_names()
    |> Enum.flat_map(&find_queries_for_field(path, &1))
    |> Enum.take(@max_query_usages)
  end

  defp extract_field_names(files) do
    files
    |> Enum.flat_map(&extract_fields_from_file/1)
    |> Enum.uniq()
  end

  defp extract_fields_from_file(file) do
    case File.read(file) do
      {:ok, content} ->
        ~r/field\s+:(\w+)/
        |> Regex.scan(content)
        |> Enum.map(fn [_, name] -> name end)

      _ ->
        []
    end
  end

  defp find_queries_for_field(path, field) do
    ["where", "order_by", "select", "group_by"]
    |> Enum.flat_map(fn query_type ->
      pattern = "#{query_type}.*:#{field}"

      path
      |> search_elixir_files(pattern, max_count: 5)
      |> Enum.map(&build_query_usage(field, pattern, &1))
    end)
  end

  defp build_query_usage(field, pattern, result) do
    %{field: field, file: result.file, pattern: pattern, matches: result.matches}
  end

  defp find_side_effects(path) do
    %{
      notifications: search_for_side_effect(path, "Notifier|Mailer|send_email|deliver"),
      workers: search_for_side_effect(path, "Oban.Worker|perform|enqueue"),
      external_apis: search_for_side_effect(path, "Req\\.|HTTPoison|Tesla|webhook|api_call")
    }
  end

  defp search_for_side_effect(path, pattern) do
    search_elixir_files(path, pattern, max_count: @max_side_effects)
  end

  defp search_elixir_files(path, pattern, opts \\ []) do
    search_opts = Keyword.merge([path: path, type: "elixir"], opts)

    case Ripgrep.search(pattern, search_opts) do
      {:ok, results} -> results
      _ -> []
    end
  end

  defp extract_module_name(file) do
    with {:ok, content} <- File.read(file),
         [_, module] <- Regex.run(~r/defmodule\s+([\w.]+)/, content) do
      module
    else
      _ -> nil
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
    [
      format_direct_deps(info.direct),
      format_indirect_deps(info.indirect),
      format_query_usages(info.queries),
      format_side_effects(info.side_effects)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp format_direct_deps([]) do
    "## Direct Dependencies\nNo direct dependencies found."
  end

  defp format_direct_deps(deps) do
    content =
      Enum.map_join(deps, "\n", fn dep ->
        "- #{dep.dependent_file} (#{dep.type}) → depends on #{dep.source_file}"
      end)

    "## Direct Dependencies\n#{content}"
  end

  defp format_indirect_deps([]), do: nil

  defp format_indirect_deps(deps) do
    content =
      Enum.map_join(deps, "\n", fn dep ->
        "- #{dep.dependent_file} → indirectly depends on #{dep.source_file}"
      end)

    "## Indirect Dependencies\n#{content}"
  end

  defp format_query_usages([]), do: nil

  defp format_query_usages(queries) do
    content = Enum.map_join(queries, "\n", fn q -> "- #{q.file}: query on :#{q.field}" end)
    "## Query Usages\n#{content}"
  end

  defp format_side_effects(effects) do
    """
    ## Side Effects

    ### Notifications
    #{format_effect_list(effects.notifications)}

    ### Background Workers
    #{format_effect_list(effects.workers)}

    ### External APIs
    #{format_effect_list(effects.external_apis)}
    """
  end

  defp format_effect_list([]), do: "None found."

  defp format_effect_list(results) do
    results
    |> Enum.take(@max_displayed_side_effects)
    |> Enum.map_join("\n", fn r -> "- #{r.file}" end)
  end
end
