defmodule Albedo.Agents.TechStack do
  @moduledoc """
  Phase 1a: Tech Stack Detection Agent.
  Identifies all technologies, frameworks, libraries, and versions used.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts
  alias Albedo.Search.{FileScanner, PatternMatcher}

  @impl Albedo.Agents.Base
  def investigate(state) do
    path = state.codebase_path
    task = state.task

    with {:ok, file_stats} <- FileScanner.count_by_language(path),
         {:ok, files} <- FileScanner.list_files(path),
         {:ok, tree} <- FileScanner.tree(path, max_depth: 3),
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
    package_files = [
      "mix.exs",
      "package.json",
      "requirements.txt",
      "pyproject.toml",
      "Gemfile",
      "go.mod",
      "Cargo.toml"
    ]

    package_files
    |> Enum.map(fn file ->
      full_path = Path.join(path, file)

      case File.read(full_path) do
        {:ok, content} -> {file, content}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn {_, content} -> content end)
  end

  defp read_config_files(path) do
    config_patterns = [
      "config/*.exs",
      "config.exs",
      ".tool-versions",
      ".env.example",
      "docker-compose.yml",
      "Dockerfile"
    ]

    config_patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(path, pattern))
    end)
    |> Enum.map(fn file ->
      case File.read(file) do
        {:ok, content} -> content
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_dependencies(_path, package_contents) do
    mix_content =
      package_contents
      |> Enum.find(fn content ->
        String.contains?(content, "defmodule") and String.contains?(content, "MixProject")
      end)

    if mix_content do
      PatternMatcher.extract_mix_deps(mix_content)
    else
      []
    end
  end

  defp summarize_package_files(contents) do
    Enum.map_join(contents, "\n---\n", &String.slice(&1, 0, 2000))
  end

  defp summarize_config_files(contents) do
    Enum.map_join(contents, "\n---\n", &String.slice(&1, 0, 1000))
  end
end
