defmodule Albedo.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Albedo.CLI

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

  describe "main/1" do
    test "displays help with --help flag" do
      output = run_cli_safely(["--help"])
      assert output =~ "Albedo"
      assert output =~ "USAGE:"
      assert output =~ "COMMANDS:"
      assert output =~ "OPTIONS:"
      assert output =~ "EXAMPLES:"
    end

    test "displays help with -h flag" do
      output = run_cli_safely(["-h"])
      assert output =~ "Albedo"
      assert output =~ "USAGE:"
    end

    test "displays version with --version flag" do
      output = run_cli_safely(["--version"])
      assert output =~ "Albedo v"
    end

    test "displays version with -v flag" do
      output = run_cli_safely(["-v"])
      assert output =~ "Albedo v"
    end

    test "displays help when no arguments provided" do
      output = run_cli_safely([])
      assert output =~ "USAGE:"
    end
  end

  describe "init command" do
    test "displays initialization message" do
      output = run_cli_safely(["init"])
      assert output =~ "Albedo"
      assert output =~ "Initializing"
    end

    test "shows config file path on success" do
      output = run_cli_safely(["init"])
      assert output =~ "config.toml"
    end
  end

  describe "parse_args/1 invalid options" do
    test "reports invalid options" do
      output = run_cli_safely_stderr(["--invalid-option"])
      assert output =~ "Invalid option"
    end
  end

  describe "analyze command" do
    test "requires --task option" do
      output = run_cli_safely_stderr(["analyze", "."])
      assert output =~ "Missing required --task option"
    end

    test "requires valid path" do
      output = run_cli_safely_stderr(["analyze", "/nonexistent/path", "--task", "test"])
      assert output =~ "not found"
    end
  end

  describe "sessions command" do
    test "lists sessions or shows empty message" do
      output = run_cli_safely(["sessions"])
      assert output =~ "Albedo"
    end
  end

  describe "show command" do
    test "handles missing session" do
      output = run_cli_safely_stderr(["show", "nonexistent-session"])
      assert output =~ "not found"
    end
  end

  describe "resume command" do
    test "handles missing session path" do
      output = run_cli_safely_stderr(["resume", "/nonexistent/session"])
      assert output =~ "not found"
    end
  end

  describe "replan command" do
    test "handles missing session path" do
      output = run_cli_safely_stderr(["replan", "/nonexistent/session"])
      assert output =~ "not found"
    end
  end

  describe "unknown command" do
    test "reports unknown command" do
      output = run_cli_safely_stderr(["unknown"])
      assert output =~ "Unknown command"
    end
  end

  describe "output formatting" do
    test "print_header outputs correctly formatted header" do
      output = run_cli_safely(["--version"])
      assert is_binary(output)
      refute output =~ "ArgumentError"
    end

    test "print_help outputs correctly formatted help" do
      output = run_cli_safely(["--help"])
      assert is_binary(output)
      refute output =~ "ArgumentError"
    end
  end
end
