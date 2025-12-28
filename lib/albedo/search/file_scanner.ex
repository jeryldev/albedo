defmodule Albedo.Search.FileScanner do
  @moduledoc """
  File system scanning for codebase analysis.
  """

  @default_exclude [
    "node_modules",
    "_build",
    "deps",
    ".git",
    "priv/static",
    ".elixir_ls",
    "cover",
    "doc",
    ".DS_Store"
  ]

  @language_extensions %{
    "elixir" => [".ex", ".exs"],
    "javascript" => [".js", ".jsx", ".mjs"],
    "typescript" => [".ts", ".tsx"],
    "python" => [".py"],
    "ruby" => [".rb"],
    "go" => [".go"],
    "rust" => [".rs"],
    "html" => [".html", ".heex", ".eex", ".leex"],
    "css" => [".css", ".scss", ".sass"],
    "json" => [".json"],
    "yaml" => [".yml", ".yaml"],
    "markdown" => [".md", ".markdown"],
    "sql" => [".sql"]
  }

  @doc """
  Scan a directory and return a tree structure.
  """
  def scan_directory(path, opts \\ []) do
    exclude = opts[:exclude] || @default_exclude
    max_depth = opts[:max_depth] || 10

    case File.stat(path) do
      {:ok, %{type: :directory}} ->
        {:ok, scan_dir_recursive(path, exclude, max_depth, 0, "")}

      {:ok, %{type: :regular}} ->
        {:ok, file_info(path)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a flat list of all files in a directory.
  """
  def list_files(path, opts \\ []) do
    exclude = opts[:exclude] || @default_exclude
    extensions = opts[:extensions]

    files =
      path
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&excluded?(&1, exclude))
      |> filter_by_extension(extensions)
      |> Enum.sort()

    {:ok, files}
  end

  @doc """
  Count files by extension/language.
  """
  def count_by_language(path, opts \\ []) do
    {:ok, files} = list_files(path, opts)

    counts =
      files
      |> Enum.map(&Path.extname/1)
      |> Enum.reduce(%{}, fn ext, acc ->
        Map.update(acc, ext, 1, &(&1 + 1))
      end)

    language_counts =
      Enum.reduce(@language_extensions, %{}, fn {lang, exts}, acc ->
        count = Enum.reduce(exts, 0, fn ext, sum -> sum + Map.get(counts, ext, 0) end)
        if count > 0, do: Map.put(acc, lang, count), else: acc
      end)

    {:ok, %{by_extension: counts, by_language: language_counts, total: length(files)}}
  end

  @doc """
  Find specific files by name pattern.
  """
  def find_files(path, pattern, opts \\ []) do
    exclude = opts[:exclude] || @default_exclude

    files =
      path
      |> Path.join("**/" <> pattern)
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&excluded?(&1, exclude))
      |> Enum.sort()

    {:ok, files}
  end

  @doc """
  Read file content with optional line range.
  """
  def read_file(path, opts \\ []) do
    start_line = opts[:start] || 1
    end_line = opts[:end]

    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n")

        selected =
          lines
          |> Enum.with_index(1)
          |> Enum.filter(fn {_, idx} ->
            idx >= start_line and (is_nil(end_line) or idx <= end_line)
          end)
          |> Enum.map_join("\n", fn {line, idx} -> "#{idx}: #{line}" end)

        {:ok, selected}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get directory structure as a formatted tree string.
  """
  def tree(path, opts \\ []) do
    exclude = opts[:exclude] || @default_exclude
    max_depth = opts[:max_depth] || 3

    tree_string = build_tree_string(path, exclude, max_depth, 0, "")
    {:ok, tree_string}
  end

  @doc """
  Detect if path is an Elixir/Phoenix project.
  """
  def detect_project_type(path) do
    {:ok, detect_type(path)}
  end

  defp detect_type(path) do
    cond do
      File.exists?(Path.join(path, "mix.exs")) -> detect_elixir_type(path)
      File.exists?(Path.join(path, "package.json")) -> :node
      File.exists?(Path.join(path, "requirements.txt")) -> :python
      File.exists?(Path.join(path, "pyproject.toml")) -> :python
      File.exists?(Path.join(path, "Gemfile")) -> :ruby
      File.exists?(Path.join(path, "go.mod")) -> :go
      File.exists?(Path.join(path, "Cargo.toml")) -> :rust
      true -> :unknown
    end
  end

  defp detect_elixir_type(path) do
    cond do
      File.exists?(Path.join(path, "apps")) -> :umbrella
      has_phoenix?(path) -> :phoenix
      true -> :elixir
    end
  end

  defp scan_dir_recursive(_path, _exclude, max_depth, depth, _) when depth >= max_depth do
    %{type: :truncated, reason: :max_depth}
  end

  defp scan_dir_recursive(path, exclude, max_depth, depth, _) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&excluded?(&1, exclude))
        |> Enum.sort()
        |> Enum.map(&process_entry(&1, path, exclude, max_depth, depth))
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp process_entry(entry, path, exclude, max_depth, depth) do
    full_path = Path.join(path, entry)

    case File.stat(full_path) do
      {:ok, %{type: :directory}} ->
        %{
          name: entry,
          type: :directory,
          children: scan_dir_recursive(full_path, exclude, max_depth, depth + 1, entry)
        }

      {:ok, %{type: :regular}} ->
        file_info(full_path)

      _ ->
        nil
    end
  end

  defp file_info(path) do
    %{
      name: Path.basename(path),
      type: :file,
      extension: Path.extname(path),
      size: file_size(path)
    }
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp excluded?(path, exclude) do
    name = Path.basename(path)
    path_parts = Path.split(path)

    Enum.any?(exclude, fn pattern ->
      name == pattern or pattern in path_parts
    end)
  end

  defp filter_by_extension(files, nil), do: files

  defp filter_by_extension(files, extensions) when is_list(extensions) do
    Enum.filter(files, fn file ->
      Path.extname(file) in extensions
    end)
  end

  defp build_tree_string(path, exclude, max_depth, depth, prefix) when depth < max_depth do
    case File.ls(path) do
      {:ok, entries} ->
        filtered = Enum.reject(entries, &excluded?(&1, exclude)) |> Enum.sort()
        total = length(filtered)

        filtered
        |> Enum.with_index()
        |> Enum.map(&render_tree_entry(&1, path, exclude, max_depth, depth, prefix, total))
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      {:error, _} ->
        ""
    end
  end

  defp build_tree_string(_, _, _, _, _), do: ""

  defp render_tree_entry({entry, idx}, path, exclude, max_depth, depth, prefix, total) do
    full_path = Path.join(path, entry)
    is_last = idx == total - 1
    connector = if is_last, do: "└── ", else: "├── "
    next_prefix = if is_last, do: "    ", else: "│   "

    case File.stat(full_path) do
      {:ok, %{type: :directory}} ->
        dir_content =
          build_tree_string(full_path, exclude, max_depth, depth + 1, prefix <> next_prefix)

        "#{prefix}#{connector}#{entry}/\n#{dir_content}"

      {:ok, %{type: :regular}} ->
        "#{prefix}#{connector}#{entry}"

      _ ->
        nil
    end
  end

  defp has_phoenix?(path) do
    mix_file = Path.join(path, "mix.exs")

    case File.read(mix_file) do
      {:ok, content} -> String.contains?(content, ":phoenix")
      _ -> false
    end
  end
end
