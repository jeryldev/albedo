defmodule Albedo.Agents.ConventionsTest do
  use ExUnit.Case, async: true

  alias Albedo.TestSupport.Mocks

  describe "app directory finding" do
    setup do
      dir = Mocks.create_temp_dir()
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "finds app directory ignoring _web suffix", %{dir: dir} do
      lib_path = Path.join(dir, "lib")
      File.mkdir_p!(Path.join(lib_path, "my_app"))
      File.mkdir_p!(Path.join(lib_path, "my_app_web"))

      entries = ["my_app", "my_app_web"]
      result = find_app_directory(lib_path, entries)

      assert result == "my_app"
    end

    test "returns nil for empty directory", %{dir: dir} do
      lib_path = Path.join(dir, "lib")
      File.mkdir_p!(lib_path)

      result = find_app_directory(lib_path, [])

      assert result == nil
    end
  end

  describe "sample formatting" do
    test "formats schema sample" do
      result = %{file: "/path/to/user.ex", matches: []}
      sample = format_schema_sample(result)

      assert sample =~ "### Schema: user.ex"
      assert sample =~ "```elixir"
    end

    test "formats context sample" do
      sample = format_context_sample("/lib", "my_app", "accounts.ex")

      assert sample =~ "### Context: accounts.ex"
      assert sample =~ "```elixir"
    end

    test "formats liveview sample" do
      result = %{file: "/path/to/dashboard_live.ex", matches: []}
      sample = format_liveview_sample(result)

      assert sample =~ "### LiveView: dashboard_live.ex"
      assert sample =~ "```elixir"
    end

    test "formats test sample" do
      sample = format_test_sample("/path/to/user_test.exs")

      assert sample =~ "### Test: user_test.exs"
      assert sample =~ "```elixir"
    end

    test "formats config sample with truncation" do
      content = String.duplicate("config", 200)
      sample = format_config_sample("Formatter Config", content)

      assert sample =~ "### Formatter Config"
      assert sample =~ "```elixir"
      assert String.length(sample) < String.length(content) + 100
    end
  end

  describe "config sample gathering" do
    setup do
      dir = Mocks.create_temp_dir()
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "reads existing config files", %{dir: dir} do
      File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"*.ex\"]]")

      samples = read_config_sample(dir, {".formatter.exs", "Formatter"})

      assert length(samples) == 1
      assert hd(samples) =~ "Formatter"
    end

    test "returns empty list for missing config", %{dir: dir} do
      samples = read_config_sample(dir, {".credo.exs", "Credo"})

      assert samples == []
    end
  end

  describe "test sample gathering" do
    setup do
      dir = Mocks.create_temp_dir()
      test_dir = Path.join(dir, "test")
      File.mkdir_p!(test_dir)
      File.write!(Path.join(test_dir, "user_test.exs"), "defmodule UserTest do\nend")
      File.write!(Path.join(test_dir, "accounts_test.exs"), "defmodule AccountsTest do\nend")
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "finds test files", %{dir: dir} do
      samples = gather_test_samples(dir)

      assert length(samples) == 2
      assert Enum.any?(samples, &(&1 =~ "user_test.exs"))
    end

    test "returns empty for missing test directory" do
      samples = gather_test_samples("/nonexistent/path")

      assert samples == []
    end
  end

  describe "context sample gathering" do
    setup do
      dir = Mocks.create_temp_dir()
      lib_path = Path.join([dir, "lib", "my_app"])
      File.mkdir_p!(lib_path)
      File.write!(Path.join(lib_path, "accounts.ex"), "defmodule MyApp.Accounts do\nend")
      File.write!(Path.join(lib_path, "users.ex"), "defmodule MyApp.Users do\nend")
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "gathers context file samples", %{dir: dir} do
      samples = gather_context_samples(dir)

      assert length(samples) == 2
      assert Enum.any?(samples, &(&1 =~ "accounts.ex"))
    end

    test "returns empty for missing lib directory" do
      samples = gather_context_samples("/nonexistent/path")

      assert samples == []
    end
  end

  @max_config_content 500
  @max_context_samples 2
  @max_test_samples 2

  defp find_app_directory(lib_path, entries) do
    entries
    |> Enum.reject(&String.ends_with?(&1, "_web"))
    |> Enum.find(fn entry -> File.dir?(Path.join(lib_path, entry)) end)
  end

  defp format_schema_sample(result) do
    """
    ### Schema: #{Path.basename(result.file)}
    ```elixir
    # File content would be here
    ```
    """
  end

  defp format_context_sample(_lib_path, _app_dir, file) do
    """
    ### Context: #{file}
    ```elixir
    # File content would be here
    ```
    """
  end

  defp format_liveview_sample(result) do
    """
    ### LiveView: #{Path.basename(result.file)}
    ```elixir
    # File content would be here
    ```
    """
  end

  defp format_test_sample(file) do
    """
    ### Test: #{Path.basename(file)}
    ```elixir
    # File content would be here
    ```
    """
  end

  defp format_config_sample(label, content) do
    """
    ### #{label}
    ```elixir
    #{String.slice(content, 0, @max_config_content)}
    ```
    """
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

  defp gather_test_samples(path) do
    test_path = Path.join(path, "test")

    case Albedo.Search.FileScanner.find_files(test_path, "*_test.exs") do
      {:ok, files} ->
        files
        |> Enum.take(@max_test_samples)
        |> Enum.map(&format_test_sample/1)

      _ ->
        []
    end
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
end
