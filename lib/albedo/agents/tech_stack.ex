defmodule Albedo.Agents.TechStack do
  @moduledoc """
  Phase 1a: Tech Stack Detection Agent.
  Identifies all technologies, frameworks, libraries, and versions used.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts
  alias Albedo.Search.{FileScanner, PatternMatcher}

  @max_tree_depth 3
  @max_package_content 2000
  @max_config_content 1000
  @greenfield_max_tokens 8192

  @package_files ~w(mix.exs package.json requirements.txt pyproject.toml Gemfile go.mod Cargo.toml)
  @config_patterns ~w(config/*.exs config.exs .tool-versions .env.example docker-compose.yml Dockerfile)

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

    prompt = Prompts.tech_stack(task, %{}, context)

    case call_llm(prompt, max_tokens: @greenfield_max_tokens) do
      {:ok, response} ->
        findings = %{
          greenfield: true,
          recommended_stack: context[:stack],
          database: context[:database],
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

    with {:ok, file_stats} <- FileScanner.count_by_language(path),
         {:ok, files} <- FileScanner.list_files(path),
         {:ok, tree} <- FileScanner.tree(path, max_depth: @max_tree_depth),
         {:ok, project_type} <- FileScanner.detect_project_type(path) do
      package_contents = read_package_files(path)
      config_contents = read_config_files(path)

      frameworks =
        PatternMatcher.detect_frameworks(path, files, package_contents ++ config_contents)

      database = PatternMatcher.detect_database(config_contents)
      infrastructure = PatternMatcher.detect_infrastructure(path, files)

      elixir_version = PatternMatcher.extract_elixir_version(path)
      deps = extract_dependencies(path, package_contents)

      codebase_info = %{
        project_type: project_type,
        file_stats: file_stats,
        tree: tree,
        frameworks: frameworks,
        database: database,
        infrastructure: infrastructure,
        elixir_version: elixir_version,
        dependencies: deps,
        package_files: summarize_package_files(package_contents),
        config_files: summarize_config_files(config_contents)
      }

      prompt = Prompts.tech_stack(task, codebase_info)

      case call_llm(prompt) do
        {:ok, response} ->
          findings = %{
            project_type: project_type,
            file_stats: file_stats,
            frameworks: frameworks,
            database: database,
            infrastructure: infrastructure,
            elixir_version: elixir_version,
            dependencies: deps,
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

  defp read_package_files(path) do
    @package_files
    |> Enum.flat_map(&read_file_content(path, &1))
  end

  defp read_config_files(path) do
    @config_patterns
    |> Enum.flat_map(fn pattern -> Path.wildcard(Path.join(path, pattern)) end)
    |> Enum.flat_map(&read_file/1)
  end

  defp read_file_content(path, file) do
    case File.read(Path.join(path, file)) do
      {:ok, content} -> [content]
      _ -> []
    end
  end

  defp read_file(file) do
    case File.read(file) do
      {:ok, content} -> [content]
      _ -> []
    end
  end

  defp extract_dependencies(_path, package_contents) do
    package_contents
    |> Enum.find(&mix_project_content?/1)
    |> case do
      nil -> []
      content -> PatternMatcher.extract_mix_deps(content)
    end
  end

  defp mix_project_content?(content) do
    String.contains?(content, "defmodule") and String.contains?(content, "MixProject")
  end

  defp summarize_package_files(contents) do
    Enum.map_join(contents, "\n---\n", &String.slice(&1, 0, @max_package_content))
  end

  defp summarize_config_files(contents) do
    Enum.map_join(contents, "\n---\n", &String.slice(&1, 0, @max_config_content))
  end
end
