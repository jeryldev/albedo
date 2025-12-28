defmodule Albedo.Search.Ripgrep do
  @moduledoc """
  Wrapper for ripgrep (rg) for fast codebase searching.
  """

  require Logger

  @default_exclude_patterns [
    "node_modules",
    "_build",
    "deps",
    ".git",
    "priv/static",
    ".elixir_ls",
    "cover",
    "doc"
  ]

  # Characters that could be dangerous in shell contexts
  @dangerous_chars [?`, ?$, ?;, ?&, ?|, ?>, ?<, ?\n, ?\r, ?\0]

  @doc """
  Check if ripgrep is available on the system.
  """
  def available? do
    case System.cmd("which", ["rg"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Search for a pattern in the codebase.

  Options:
    - :path - Directory to search (required)
    - :type - File type filter (e.g., "elixir", "js")
    - :glob - Glob pattern for files
    - :context - Number of context lines (default: 2)
    - :max_count - Maximum matches per file
    - :exclude - Additional patterns to exclude
    - :case_insensitive - Case insensitive search (default: false)
  """
  def search(pattern, opts \\ []) when is_binary(pattern) and is_list(opts) do
    with :ok <- validate_pattern(pattern) do
      path = opts[:path] || File.cwd!()
      context = opts[:context] || 2
      max_count = opts[:max_count]
      file_type = opts[:type]
      glob = opts[:glob]
      case_insensitive = opts[:case_insensitive] || false
      extra_exclude = opts[:exclude] || []

      args =
        ["--json", "-C", to_string(context)]
        |> add_type_filter(file_type)
        |> add_glob_filter(glob)
        |> add_max_count(max_count)
        |> add_case_flag(case_insensitive)
        |> add_exclude_patterns(extra_exclude)
        |> Kernel.++([pattern, path])

      case System.cmd("rg", args, stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, parse_json_output(output)}

        {_output, 1} ->
          {:ok, []}

        {output, _} ->
          Logger.warning("ripgrep error: #{output}")
          {:error, output}
      end
    end
  end

  @doc """
  Validates a search pattern for dangerous characters.
  Returns :ok if safe, {:error, reason} if dangerous.
  """
  def validate_pattern(pattern) when is_binary(pattern) do
    if safe_pattern?(pattern) do
      :ok
    else
      {:error, :dangerous_pattern}
    end
  end

  defp safe_pattern?(pattern) do
    pattern
    |> String.to_charlist()
    |> Enum.all?(fn char -> char not in @dangerous_chars end)
  end

  @doc """
  Search for multiple patterns and combine results.
  """
  def search_multiple(patterns, opts \\ []) when is_list(patterns) do
    results =
      patterns
      |> Enum.map(&search(&1, opts))
      |> Enum.reduce({:ok, []}, fn
        {:ok, matches}, {:ok, acc} -> {:ok, acc ++ matches}
        {:error, _} = error, _ -> error
        _, {:error, _} = error -> error
      end)

    case results do
      {:ok, matches} -> {:ok, deduplicate_matches(matches)}
      error -> error
    end
  end

  @doc """
  Search for files matching a pattern.
  """
  def find_files(pattern, opts \\ []) do
    path = opts[:path] || File.cwd!()
    file_type = opts[:type]
    glob = opts[:glob]
    extra_exclude = opts[:exclude] || []

    args =
      ["--files", "-g", pattern]
      |> add_type_filter(file_type)
      |> add_glob_filter(glob)
      |> add_exclude_patterns(extra_exclude)
      |> Kernel.++([path])

    case System.cmd("rg", args, stderr_to_stdout: true) do
      {output, 0} ->
        files =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)

        {:ok, files}

      {_, 1} ->
        {:ok, []}

      {output, _} ->
        Logger.warning("ripgrep find_files error: #{output}")
        {:error, output}
    end
  end

  @doc """
  Get file content with line numbers for a specific file.
  """
  def read_file_with_lines(file_path, opts \\ []) do
    start_line = opts[:start] || 1
    end_line = opts[:end]

    case File.read(file_path) do
      {:ok, content} ->
        lines =
          content
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.filter(fn {_, idx} ->
            idx >= start_line and (is_nil(end_line) or idx <= end_line)
          end)
          |> Enum.map(fn {line, idx} -> {idx, line} end)

        {:ok, lines}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_type_filter(args, nil), do: args
  defp add_type_filter(args, type), do: args ++ ["--type", type]

  defp add_glob_filter(args, nil), do: args
  defp add_glob_filter(args, glob), do: args ++ ["-g", glob]

  defp add_max_count(args, nil), do: args
  defp add_max_count(args, count), do: args ++ ["-m", to_string(count)]

  defp add_case_flag(args, false), do: args
  defp add_case_flag(args, true), do: args ++ ["-i"]

  defp add_exclude_patterns(args, extra) do
    patterns = @default_exclude_patterns ++ extra

    Enum.reduce(patterns, args, fn pattern, acc ->
      acc ++ ["-g", "!#{pattern}"]
    end)
  end

  defp parse_json_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_json_line/1)
    |> Enum.reject(&is_nil/1)
    |> group_by_file()
  end

  defp parse_json_line(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "match"} = data} ->
        %{
          type: :match,
          file: get_in(data, ["data", "path", "text"]),
          line_number: get_in(data, ["data", "line_number"]),
          content: get_in(data, ["data", "lines", "text"]),
          submatches:
            get_in(data, ["data", "submatches"])
            |> Enum.map(fn m -> m["match"]["text"] end)
        }

      {:ok, %{"type" => "context"} = data} ->
        %{
          type: :context,
          file: get_in(data, ["data", "path", "text"]),
          line_number: get_in(data, ["data", "line_number"]),
          content: get_in(data, ["data", "lines", "text"])
        }

      {:ok, %{"type" => "begin"}} ->
        nil

      {:ok, %{"type" => "end"}} ->
        nil

      {:ok, %{"type" => "summary"}} ->
        nil

      _ ->
        nil
    end
  end

  defp group_by_file(matches) do
    matches
    |> Enum.group_by(& &1.file)
    |> Enum.map(fn {file, file_matches} ->
      %{
        file: file,
        matches:
          file_matches
          |> Enum.filter(&(&1.type == :match))
          |> Enum.map(fn m ->
            %{
              line: m.line_number,
              content: String.trim(m.content),
              submatches: m.submatches
            }
          end),
        context:
          file_matches
          |> Enum.sort_by(& &1.line_number)
          |> Enum.map(fn m ->
            %{
              line: m.line_number,
              content: String.trim(m.content),
              is_match: m.type == :match
            }
          end)
      }
    end)
  end

  defp deduplicate_matches(matches) do
    matches
    |> Enum.group_by(& &1.file)
    |> Enum.map(fn {file, file_matches} ->
      all_matches =
        file_matches
        |> Enum.flat_map(& &1.matches)
        |> Enum.uniq_by(& &1.line)
        |> Enum.sort_by(& &1.line)

      all_context =
        file_matches
        |> Enum.flat_map(& &1.context)
        |> Enum.uniq_by(& &1.line)
        |> Enum.sort_by(& &1.line)

      %{file: file, matches: all_matches, context: all_context}
    end)
  end
end
