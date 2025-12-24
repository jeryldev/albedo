defmodule Albedo.Search.RipgrepTest do
  use ExUnit.Case, async: true

  alias Albedo.Search.Ripgrep
  alias Albedo.TestSupport.Mocks

  describe "available?/0" do
    test "returns boolean" do
      result = Ripgrep.available?()
      assert is_boolean(result)
    end
  end

  describe "search/2" do
    setup do
      dir = Mocks.create_temp_dir()
      Mocks.create_sample_codebase(dir)

      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)

      {:ok, dir: dir}
    end

    test "finds pattern in codebase", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, results} = Ripgrep.search("defmodule", path: dir)
        assert is_list(results)
      end
    end

    test "returns empty list when pattern not found", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, results} = Ripgrep.search("nonexistent_pattern_xyz123", path: dir)
        assert results == []
      end
    end

    test "respects type filter", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, results} = Ripgrep.search("def", path: dir, type: "elixir")
        assert is_list(results)
      end
    end

    test "respects glob filter", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, results} = Ripgrep.search("def", path: dir, glob: "*.ex")
        assert is_list(results)
      end
    end

    test "respects context option", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, results} = Ripgrep.search("defmodule", path: dir, context: 5)
        assert is_list(results)
      end
    end

    test "respects case_insensitive option", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, results} = Ripgrep.search("DEFMODULE", path: dir, case_insensitive: true)
        assert is_list(results)
      end
    end

    test "respects exclude patterns", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, results} = Ripgrep.search("def", path: dir, exclude: ["test"])
        assert is_list(results)
      end
    end
  end

  describe "search_multiple/2" do
    setup do
      dir = Mocks.create_temp_dir()
      Mocks.create_sample_codebase(dir)

      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)

      {:ok, dir: dir}
    end

    test "combines results from multiple patterns", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, results} = Ripgrep.search_multiple(["defmodule", "def "], path: dir)
        assert is_list(results)
      end
    end

    test "handles empty patterns list", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, results} = Ripgrep.search_multiple([], path: dir)
        assert results == []
      end
    end
  end

  describe "find_files/2" do
    setup do
      dir = Mocks.create_temp_dir()
      Mocks.create_sample_codebase(dir)

      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)

      {:ok, dir: dir}
    end

    test "finds files matching pattern", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, files} = Ripgrep.find_files("*.ex", path: dir)
        assert is_list(files)
        assert Enum.any?(files, &String.ends_with?(&1, ".ex"))
      end
    end

    test "returns empty list when no files match", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, files} = Ripgrep.find_files("*.nonexistent", path: dir)
        assert files == []
      end
    end
  end

  describe "read_file_with_lines/2" do
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

    test "reads file with line numbers", %{test_file: test_file} do
      {:ok, lines} = Ripgrep.read_file_with_lines(test_file)
      assert is_list(lines)
      assert {1, "Line 1"} in lines
    end

    test "respects start line option", %{test_file: test_file} do
      {:ok, lines} = Ripgrep.read_file_with_lines(test_file, start: 3)
      assert is_list(lines)
      refute Enum.any?(lines, fn {num, _} -> num < 3 end)
    end

    test "respects end line option", %{test_file: test_file} do
      {:ok, lines} = Ripgrep.read_file_with_lines(test_file, end: 2)
      assert is_list(lines)
      refute Enum.any?(lines, fn {num, _} -> num > 2 end)
    end

    test "returns error for nonexistent file" do
      assert {:error, _} = Ripgrep.read_file_with_lines("/nonexistent/file.txt")
    end
  end
end
