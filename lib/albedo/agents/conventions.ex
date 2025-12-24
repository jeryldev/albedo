defmodule Albedo.Agents.Conventions do
  @moduledoc """
  Phase 1c: Convention Detection Agent.
  Learns the unwritten rules and patterns specific to this codebase.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts
  alias Albedo.Search.{FileScanner, Ripgrep}

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
  def format_output(findings) do
    findings.content
  end

  defp gather_code_samples(path) do
    samples = []

    samples = samples ++ gather_schema_samples(path)
    samples = samples ++ gather_context_samples(path)
    samples = samples ++ gather_liveview_samples(path)
    samples = samples ++ gather_test_samples(path)
    samples = samples ++ gather_config_samples(path)

    Enum.join(samples, "\n\n---\n\n")
  end

  defp gather_schema_samples(path) do
    case Ripgrep.search("use.*Schema|schema\\s+\"", path: path, type: "elixir", max_count: 3) do
      {:ok, results} ->
        results
        |> Enum.take(3)
        |> Enum.map(fn result ->
          content = read_file_context(result.file, result.matches)

          """
          ### Schema: #{Path.basename(result.file)}
          ```elixir
          #{content}
          ```
          """
        end)

      _ ->
        []
    end
  end

  defp gather_context_samples(path) do
    lib_path = Path.join(path, "lib")

    case File.ls(lib_path) do
      {:ok, entries} ->
        app_dir =
          entries
          |> Enum.reject(&String.ends_with?(&1, "_web"))
          |> Enum.find(fn entry -> File.dir?(Path.join(lib_path, entry)) end)

        if app_dir do
          app_path = Path.join(lib_path, app_dir)

          case File.ls(app_path) do
            {:ok, files} ->
              files
              |> Enum.filter(&String.ends_with?(&1, ".ex"))
              |> Enum.reject(&String.starts_with?(&1, "."))
              |> Enum.take(2)
              |> Enum.map(fn file ->
                full_path = Path.join(app_path, file)
                content = read_file_snippet(full_path, 100)

                """
                ### Context: #{file}
                ```elixir
                #{content}
                ```
                """
              end)

            _ ->
              []
          end
        else
          []
        end

      _ ->
        []
    end
  end

  defp gather_liveview_samples(path) do
    case Ripgrep.search("use.*LiveView|use Phoenix.LiveView",
           path: path,
           type: "elixir",
           max_count: 2
         ) do
      {:ok, results} ->
        results
        |> Enum.take(2)
        |> Enum.map(fn result ->
          content = read_file_snippet(result.file, 80)

          """
          ### LiveView: #{Path.basename(result.file)}
          ```elixir
          #{content}
          ```
          """
        end)

      _ ->
        []
    end
  end

  defp gather_test_samples(path) do
    test_path = Path.join(path, "test")

    case FileScanner.find_files(test_path, "*_test.exs") do
      {:ok, files} ->
        files
        |> Enum.take(2)
        |> Enum.map(fn file ->
          content = read_file_snippet(file, 60)

          """
          ### Test: #{Path.basename(file)}
          ```elixir
          #{content}
          ```
          """
        end)

      _ ->
        []
    end
  end

  defp gather_config_samples(path) do
    config_files = [
      {".formatter.exs", "Formatter Config"},
      {".credo.exs", "Credo Config"}
    ]

    config_files
    |> Enum.map(fn {file, label} ->
      full_path = Path.join(path, file)

      case File.read(full_path) do
        {:ok, content} ->
          """
          ### #{label}
          ```elixir
          #{String.slice(content, 0, 500)}
          ```
          """

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp read_file_context(file, matches) do
    lines =
      matches
      |> Enum.flat_map(fn match ->
        start_line = max(1, match.line - 5)
        end_line = match.line + 20

        case FileScanner.read_file(file, start: start_line, end: end_line) do
          {:ok, content} -> [content]
          _ -> []
        end
      end)

    Enum.join(lines, "\n...\n")
  end

  defp read_file_snippet(file, max_lines) do
    case FileScanner.read_file(file, start: 1, end: max_lines) do
      {:ok, content} -> content
      _ -> "# Could not read file"
    end
  end
end
