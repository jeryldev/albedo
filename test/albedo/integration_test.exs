defmodule Albedo.IntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Albedo.{Config, CLI}
  alias Albedo.Search.{FileScanner, Ripgrep}
  alias Albedo.Session.State
  alias Albedo.TestSupport.Mocks

  defp run_cli_safely(args) do
    capture_io(fn ->
      try do
        CLI.main(args)
      catch
        :throw, {:cli_halt, _} -> :ok
        :exit, _ -> :ok
      end
    end)
  end

  defp run_cli_safely_stderr(args) do
    {stderr, _} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        capture_io(fn ->
          try do
            CLI.main(args)
          catch
            :throw, {:cli_halt, _} -> :ok
            :exit, _ -> :ok
          end
        end)
      end)

    stderr
  end

  describe "CLI help and version" do
    test "help command outputs without errors" do
      output = run_cli_safely(["--help"])
      assert output =~ "Albedo"
      assert output =~ "COMMANDS"
      refute output =~ "ArgumentError"
    end

    test "version command outputs without errors" do
      output = run_cli_safely(["--version"])
      assert output =~ "Albedo v"
      refute output =~ "ArgumentError"
    end

    test "init command runs without crashing" do
      output = run_cli_safely(["init"])
      assert output =~ "config"
      refute output =~ "ArgumentError"
    end
  end

  describe "config loading" do
    test "config loads successfully" do
      {:ok, config} = Config.load()
      assert is_map(config)
      assert config["llm"]["provider"] in ["gemini", "claude", "openai"]
    end

    test "config has required structure" do
      {:ok, config} = Config.load()

      assert Map.has_key?(config, "llm")
      assert Map.has_key?(config, "output")
      assert Map.has_key?(config, "search")
      assert Map.has_key?(config, "agents")
    end
  end

  describe "file scanning integration" do
    setup do
      dir = Mocks.create_temp_dir()
      Mocks.create_sample_codebase(dir)
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "scan and analyze sample codebase", %{dir: dir} do
      {:ok, files} = FileScanner.list_files(dir)
      refute Enum.empty?(files)

      {:ok, counts} = FileScanner.count_by_language(dir)
      assert counts.total > 0

      {:ok, project_type} = FileScanner.detect_project_type(dir)
      assert project_type == :elixir
    end

    test "search sample codebase with ripgrep", %{dir: dir} do
      if Ripgrep.available?() do
        {:ok, results} = Ripgrep.search("defmodule", path: dir)
        assert is_list(results)
      end
    end
  end

  describe "session state integration" do
    setup do
      dir = Mocks.create_temp_dir()
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "create, save, and load session state", %{dir: dir} do
      codebase_path = "/test/codebase"
      task = "Add a new feature"

      state = State.new(codebase_path, task, [])
      state = %{state | session_dir: dir}

      :ok = State.save(state)

      {:ok, loaded_state} = State.load(dir)

      assert loaded_state.codebase_path == codebase_path
      assert loaded_state.task == task
      assert loaded_state.id == state.id
    end

    test "session state phase progression", %{dir: dir} do
      state = State.new("/test", "Test task", [])
      state = %{state | session_dir: dir}

      assert State.first_incomplete_phase(state) == :domain_research

      state =
        state
        |> State.start_phase(:domain_research)
        |> State.complete_phase(:domain_research, %{content: "Research done"})

      assert State.first_incomplete_phase(state) == :tech_stack

      state =
        state
        |> State.start_phase(:tech_stack)
        |> State.complete_phase(:tech_stack, %{stack: "Elixir"})

      assert State.first_incomplete_phase(state) == :architecture
    end
  end

  describe "output formatting" do
    test "Owl.IO.puts handles tagged data correctly" do
      output =
        capture_io(fn ->
          Owl.IO.puts(Owl.Data.tag("Test message", :cyan))
        end)

      assert output =~ "Test message"
      refute output =~ "ArgumentError"
    end

    test "Owl.IO.puts handles lists of tagged data" do
      output =
        capture_io(fn ->
          Owl.IO.puts([
            Owl.Data.tag("Part 1", :cyan),
            " ",
            Owl.Data.tag("Part 2", :green)
          ])
        end)

      assert output =~ "Part 1"
      assert output =~ "Part 2"
      refute output =~ "ArgumentError"
    end
  end

  describe "error handling" do
    test "CLI handles missing task gracefully" do
      output = run_cli_safely_stderr(["analyze", "."])
      assert output =~ "Missing required --task option"
    end

    test "CLI handles nonexistent path gracefully" do
      output = run_cli_safely_stderr(["analyze", "/nonexistent/path", "--task", "test"])
      assert output =~ "not found"
    end

    test "CLI handles unknown command gracefully" do
      output = run_cli_safely_stderr(["unknowncommand"])
      assert output =~ "Unknown command"
    end
  end
end
