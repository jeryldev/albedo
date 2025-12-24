defmodule Albedo.Search.FileScannerTest do
  use ExUnit.Case, async: true

  alias Albedo.Search.FileScanner
  alias Albedo.TestSupport.Mocks

  describe "scan_directory/2" do
    setup do
      dir = Mocks.create_temp_dir()
      Mocks.create_sample_codebase(dir)

      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)

      {:ok, dir: dir}
    end

    test "scans directory successfully", %{dir: dir} do
      {:ok, result} = FileScanner.scan_directory(dir)
      assert is_list(result)
    end

    test "returns error for nonexistent path" do
      assert {:error, :enoent} = FileScanner.scan_directory("/nonexistent/path")
    end

    test "scans single file", %{dir: dir} do
      file_path = Path.join([dir, "lib", "sample_app.ex"])
      {:ok, result} = FileScanner.scan_directory(file_path)
      assert result.type == :file
      assert result.name == "sample_app.ex"
    end

    test "respects max_depth option", %{dir: dir} do
      {:ok, result} = FileScanner.scan_directory(dir, max_depth: 1)
      assert is_list(result)
    end

    test "respects exclude option", %{dir: dir} do
      {:ok, result} = FileScanner.scan_directory(dir, exclude: ["lib"])
      names = extract_names(result)
      refute "lib" in names
    end
  end

  describe "list_files/2" do
    setup do
      dir = Mocks.create_temp_dir()
      Mocks.create_sample_codebase(dir)

      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)

      {:ok, dir: dir}
    end

    test "lists all files", %{dir: dir} do
      {:ok, files} = FileScanner.list_files(dir)
      assert is_list(files)
      refute Enum.empty?(files)
    end

    test "respects extensions filter", %{dir: dir} do
      {:ok, files} = FileScanner.list_files(dir, extensions: [".ex"])
      assert Enum.all?(files, &String.ends_with?(&1, ".ex"))
    end

    test "respects exclude option", %{dir: dir} do
      {:ok, files} = FileScanner.list_files(dir, exclude: ["test"])
      refute Enum.any?(files, &String.contains?(&1, "/test/"))
    end
  end

  describe "count_by_language/2" do
    setup do
      dir = Mocks.create_temp_dir()
      Mocks.create_sample_codebase(dir)

      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)

      {:ok, dir: dir}
    end

    test "counts files by language", %{dir: dir} do
      {:ok, counts} = FileScanner.count_by_language(dir)

      assert is_map(counts.by_extension)
      assert is_map(counts.by_language)
      assert is_integer(counts.total)
      assert counts.total > 0
    end

    test "includes elixir in language counts for .ex files", %{dir: dir} do
      {:ok, counts} = FileScanner.count_by_language(dir)
      assert Map.get(counts.by_language, "elixir", 0) > 0
    end
  end

  describe "find_files/3" do
    setup do
      dir = Mocks.create_temp_dir()
      Mocks.create_sample_codebase(dir)

      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)

      {:ok, dir: dir}
    end

    test "finds files by pattern", %{dir: dir} do
      {:ok, files} = FileScanner.find_files(dir, "*.ex")
      assert is_list(files)
      refute Enum.empty?(files)
    end

    test "finds mix.exs file", %{dir: dir} do
      {:ok, files} = FileScanner.find_files(dir, "mix.exs")
      assert length(files) == 1
      assert hd(files) =~ "mix.exs"
    end

    test "returns empty list when no match", %{dir: dir} do
      {:ok, files} = FileScanner.find_files(dir, "*.nonexistent")
      assert files == []
    end
  end

  describe "read_file/2" do
    setup do
      dir = Mocks.create_temp_dir()
      test_file = Path.join(dir, "test_file.txt")

      File.write!(test_file, """
      Line 1
      Line 2
      Line 3
      Line 4
      Line 5
      """)

      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)

      {:ok, test_file: test_file}
    end

    test "reads entire file", %{test_file: test_file} do
      {:ok, content} = FileScanner.read_file(test_file)
      assert content =~ "Line 1"
      assert content =~ "Line 5"
    end

    test "respects start line option", %{test_file: test_file} do
      {:ok, content} = FileScanner.read_file(test_file, start: 3)
      refute content =~ "1: Line 1"
      assert content =~ "3: Line 3"
    end

    test "respects end line option", %{test_file: test_file} do
      {:ok, content} = FileScanner.read_file(test_file, end: 2)
      assert content =~ "1: Line 1"
      assert content =~ "2: Line 2"
      refute content =~ "3: Line 3"
    end

    test "returns error for nonexistent file" do
      assert {:error, :enoent} = FileScanner.read_file("/nonexistent/file.txt")
    end
  end

  describe "tree/2" do
    setup do
      dir = Mocks.create_temp_dir()
      Mocks.create_sample_codebase(dir)

      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)

      {:ok, dir: dir}
    end

    test "generates tree string", %{dir: dir} do
      {:ok, tree} = FileScanner.tree(dir)
      assert is_binary(tree)
      assert tree =~ "lib"
      assert tree =~ "mix.exs"
    end

    test "respects max_depth option", %{dir: dir} do
      {:ok, tree} = FileScanner.tree(dir, max_depth: 1)
      assert is_binary(tree)
    end
  end

  describe "detect_project_type/1" do
    setup do
      dir = Mocks.create_temp_dir()

      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)

      {:ok, dir: dir}
    end

    test "detects elixir project", %{dir: dir} do
      File.write!(Path.join(dir, "mix.exs"), "defmodule Test.MixProject do; end")
      assert {:ok, :elixir} = FileScanner.detect_project_type(dir)
    end

    test "detects phoenix project", %{dir: dir} do
      File.write!(Path.join(dir, "mix.exs"), "defp deps do [{:phoenix, \"~> 1.7\"}] end")
      assert {:ok, :phoenix} = FileScanner.detect_project_type(dir)
    end

    test "detects umbrella project", %{dir: dir} do
      File.write!(Path.join(dir, "mix.exs"), "defmodule Test.MixProject do; end")
      File.mkdir_p!(Path.join(dir, "apps"))
      assert {:ok, :umbrella} = FileScanner.detect_project_type(dir)
    end

    test "detects node project", %{dir: dir} do
      File.write!(Path.join(dir, "package.json"), "{}")
      assert {:ok, :node} = FileScanner.detect_project_type(dir)
    end

    test "detects python project with requirements.txt", %{dir: dir} do
      File.write!(Path.join(dir, "requirements.txt"), "flask")
      assert {:ok, :python} = FileScanner.detect_project_type(dir)
    end

    test "detects python project with pyproject.toml", %{dir: dir} do
      File.write!(Path.join(dir, "pyproject.toml"), "[project]")
      assert {:ok, :python} = FileScanner.detect_project_type(dir)
    end

    test "detects ruby project", %{dir: dir} do
      File.write!(Path.join(dir, "Gemfile"), "source 'https://rubygems.org'")
      assert {:ok, :ruby} = FileScanner.detect_project_type(dir)
    end

    test "detects go project", %{dir: dir} do
      File.write!(Path.join(dir, "go.mod"), "module test")
      assert {:ok, :go} = FileScanner.detect_project_type(dir)
    end

    test "detects rust project", %{dir: dir} do
      File.write!(Path.join(dir, "Cargo.toml"), "[package]")
      assert {:ok, :rust} = FileScanner.detect_project_type(dir)
    end

    test "returns unknown for unrecognized project", %{dir: dir} do
      assert {:ok, :unknown} = FileScanner.detect_project_type(dir)
    end
  end

  defp extract_names(items) when is_list(items) do
    Enum.flat_map(items, fn
      %{name: name, children: children} -> [name | extract_names(children)]
      %{name: name} -> [name]
      _ -> []
    end)
  end

  defp extract_names(_), do: []
end
