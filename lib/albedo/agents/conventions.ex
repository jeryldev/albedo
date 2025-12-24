defmodule Albedo.Agents.Conventions do
  @moduledoc """
  Phase 1c: Convention Detection Agent.
  Learns the unwritten rules and patterns specific to this codebase.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts
  alias Albedo.Search.{FileScanner, Ripgrep}

  @max_schema_samples 3
  @max_context_samples 2
  @max_liveview_samples 2
  @max_test_samples 2
  @max_config_content 500
  @context_lines_before 5
  @context_lines_after 20
  @context_snippet_lines 100
  @liveview_snippet_lines 80
  @test_snippet_lines 60

  @impl Albedo.Agents.Base
  def investigate(state) do
    path = state.codebase_path
    task = state.task
    previous_context = state.context

    code_samples = gather_code_samples(path)

    prompt = Prompts.conventions(task, previous_context, code_samples)

    case call_llm(prompt) do
      {:ok, response} ->
        findings = %{
          code_samples: code_samples,
          content: response
        }

        {:ok, findings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Albedo.Agents.Base
  def format_output(findings), do: findings.content

  defp gather_code_samples(path) do
    [
      gather_schema_samples(path),
      gather_context_samples(path),
      gather_liveview_samples(path),
      gather_test_samples(path),
      gather_config_samples(path)
    ]
    |> List.flatten()
    |> Enum.join("\n\n---\n\n")
  end

  defp gather_schema_samples(path) do
    pattern = "use.*Schema|schema\\s+\""

    case Ripgrep.search(pattern, path: path, type: "elixir", max_count: @max_schema_samples) do
      {:ok, results} ->
        results
        |> Enum.take(@max_schema_samples)
        |> Enum.map(&format_schema_sample/1)

      _ ->
        []
    end
  end

  defp format_schema_sample(result) do
    content = read_file_context(result.file, result.matches)

    """
    ### Schema: #{Path.basename(result.file)}
    ```elixir
    #{content}
    ```
    """
  end

  defp gather_context_samples(path) do
    lib_path = Path.join(path, "lib")

    with {:ok, entries} <- File.ls(lib_path),
         app_dir when not is_nil(app_dir) <- find_app_directory(lib_path, entries),
         {:ok, files} <- File.ls(Path.join(lib_path, app_dir)) do
      files
      |> Enum.filter(&String.ends_with?(&1, ".ex"))
      |> Enum.reject(&String.starts_with?(&1, "."))
      |> Enum.take(@max_context_samples)
      |> Enum.map(&format_context_sample(lib_path, app_dir, &1))
    else
      _ -> []
    end
  end

  defp find_app_directory(lib_path, entries) do
    entries
    |> Enum.reject(&String.ends_with?(&1, "_web"))
    |> Enum.find(fn entry -> File.dir?(Path.join(lib_path, entry)) end)
  end

  defp format_context_sample(lib_path, app_dir, file) do
    full_path = Path.join([lib_path, app_dir, file])
    content = read_file_snippet(full_path, @context_snippet_lines)

    """
    ### Context: #{file}
    ```elixir
    #{content}
    ```
    """
  end

  defp gather_liveview_samples(path) do
    pattern = "use.*LiveView|use Phoenix.LiveView"

    case Ripgrep.search(pattern, path: path, type: "elixir", max_count: @max_liveview_samples) do
      {:ok, results} ->
        results
        |> Enum.take(@max_liveview_samples)
        |> Enum.map(&format_liveview_sample/1)

      _ ->
        []
    end
  end

  defp format_liveview_sample(result) do
    content = read_file_snippet(result.file, @liveview_snippet_lines)

    """
    ### LiveView: #{Path.basename(result.file)}
    ```elixir
    #{content}
    ```
    """
  end

  defp gather_test_samples(path) do
    test_path = Path.join(path, "test")

    case FileScanner.find_files(test_path, "*_test.exs") do
      {:ok, files} ->
        files
        |> Enum.take(@max_test_samples)
        |> Enum.map(&format_test_sample/1)

      _ ->
        []
    end
  end

  defp format_test_sample(file) do
    content = read_file_snippet(file, @test_snippet_lines)

    """
    ### Test: #{Path.basename(file)}
    ```elixir
    #{content}
    ```
    """
  end

  defp gather_config_samples(path) do
    [
      {".formatter.exs", "Formatter Config"},
      {".credo.exs", "Credo Config"}
    ]
    |> Enum.flat_map(&read_config_sample(path, &1))
  end

  defp read_config_sample(path, {file, label}) do
    full_path = Path.join(path, file)

    case File.read(full_path) do
      {:ok, content} ->
        [format_config_sample(label, content)]

      _ ->
        []
    end
  end

  defp format_config_sample(label, content) do
    """
    ### #{label}
    ```elixir
    #{String.slice(content, 0, @max_config_content)}
    ```
    """
  end

  defp read_file_context(file, matches) do
    matches
    |> Enum.flat_map(fn match ->
      start_line = max(1, match.line - @context_lines_before)
      end_line = match.line + @context_lines_after

      case FileScanner.read_file(file, start: start_line, end: end_line) do
        {:ok, content} -> [content]
        _ -> []
      end
    end)
    |> Enum.join("\n...\n")
  end

  defp read_file_snippet(file, max_lines) do
    case FileScanner.read_file(file, start: 1, end: max_lines) do
      {:ok, content} -> content
      _ -> "# Could not read file"
    end
  end
end
