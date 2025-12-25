defmodule Albedo.Agents.TechStackTest do
  use ExUnit.Case, async: true

  alias Albedo.TestSupport.Mocks

  describe "mix project detection" do
    test "identifies mix project content" do
      content = """
      defmodule MyApp.MixProject do
        use Mix.Project
      end
      """

      assert mix_project_content?(content)
    end

    test "rejects non-mix content" do
      refute mix_project_content?("defmodule MyApp do\nend")
      refute mix_project_content?("package.json")
      refute mix_project_content?("")
    end
  end

  describe "summarize functions" do
    test "summarizes package files with truncation" do
      contents = [
        String.duplicate("a", 3000),
        "short content"
      ]

      result = summarize_package_files(contents)

      assert String.length(result) < 3000 + 100
      assert result =~ "---"
    end

    test "summarizes config files with truncation" do
      contents = [
        String.duplicate("config", 500),
        "import Config"
      ]

      result = summarize_config_files(contents)

      assert result =~ "---"
    end

    test "handles empty list" do
      assert summarize_package_files([]) == ""
      assert summarize_config_files([]) == ""
    end
  end

  describe "file reading" do
    setup do
      dir = Mocks.create_temp_dir()
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "reads existing package files", %{dir: dir} do
      File.write!(Path.join(dir, "mix.exs"), "defmodule App.MixProject do\nend")
      File.write!(Path.join(dir, "package.json"), ~s({"name": "app"}))

      contents = read_package_files(dir)

      assert length(contents) == 2
      assert Enum.any?(contents, &String.contains?(&1, "MixProject"))
      assert Enum.any?(contents, &String.contains?(&1, "name"))
    end

    test "returns empty list for missing files", %{dir: dir} do
      contents = read_package_files(dir)
      assert contents == []
    end

    test "reads config files from patterns", %{dir: dir} do
      config_dir = Path.join(dir, "config")
      File.mkdir_p!(config_dir)
      File.write!(Path.join(config_dir, "config.exs"), "import Config")
      File.write!(Path.join(dir, ".tool-versions"), "elixir 1.15.0")

      contents = read_config_files(dir)

      assert length(contents) >= 2
      assert Enum.any?(contents, &String.contains?(&1, "import Config"))
      assert Enum.any?(contents, &String.contains?(&1, "elixir"))
    end
  end

  describe "dependency extraction" do
    test "extracts dependencies from mix.exs content" do
      mix_content = """
      defmodule App.MixProject do
        use Mix.Project

        defp deps do
          [
            {:phoenix, "~> 1.7"},
            {:ecto, "~> 3.11"},
            {:jason, "~> 1.4"}
          ]
        end
      end
      """

      deps = extract_dependencies(".", [mix_content])

      assert is_list(deps)
    end

    test "returns empty list when no mix.exs content" do
      assert extract_dependencies(".", []) == []
      assert extract_dependencies(".", ["package.json content"]) == []
    end
  end

  @max_package_content 2000
  @max_config_content 1000
  @package_files ~w(mix.exs package.json requirements.txt pyproject.toml Gemfile go.mod Cargo.toml)
  @config_patterns ~w(config/*.exs config.exs .tool-versions .env.example docker-compose.yml Dockerfile)

  defp mix_project_content?(content) do
    String.contains?(content, "defmodule") and String.contains?(content, "MixProject")
  end

  defp summarize_package_files(contents) do
    Enum.map_join(contents, "\n---\n", &String.slice(&1, 0, @max_package_content))
  end

  defp summarize_config_files(contents) do
    Enum.map_join(contents, "\n---\n", &String.slice(&1, 0, @max_config_content))
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
      content -> Albedo.Search.PatternMatcher.extract_mix_deps(content)
    end
  end
end
