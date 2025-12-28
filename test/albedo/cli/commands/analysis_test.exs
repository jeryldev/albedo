defmodule Albedo.CLI.Commands.AnalysisTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Albedo.CLI.Commands.Analysis

  setup do
    Application.put_env(:albedo, :test_mode, true)

    on_exit(fn ->
      Application.delete_env(:albedo, :test_mode)
    end)

    :ok
  end

  defp run_analyze(path, opts) do
    capture_io(fn ->
      try do
        Analysis.analyze(path, opts)
      catch
        :throw, {:cli_halt, code} -> send(self(), {:exit_code, code})
      end
    end)
  end

  defp run_resume(path) do
    capture_io(fn ->
      try do
        Analysis.resume(path)
      catch
        :throw, {:cli_halt, code} -> send(self(), {:exit_code, code})
      end
    end)
  end

  defp run_replan(path, opts) do
    capture_io(fn ->
      try do
        Analysis.replan(path, opts)
      catch
        :throw, {:cli_halt, code} -> send(self(), {:exit_code, code})
      end
    end)
  end

  defp run_plan(opts) do
    capture_io(fn ->
      try do
        Analysis.plan(opts)
      catch
        :throw, {:cli_halt, code} -> send(self(), {:exit_code, code})
      end
    end)
  end

  describe "analyze/2" do
    test "requires --task option" do
      output = run_analyze("/some/path", [])

      assert_received {:exit_code, 1}
      assert output =~ "Missing required --task option"
      assert output =~ "Usage:"
    end

    test "shows header before error" do
      output = run_analyze("/some/path", [])

      assert output =~ "Albedo"
    end

    test "requires valid codebase path" do
      output = run_analyze("/nonexistent/path/12345", task: "test task")

      assert_received {:exit_code, 1}
      assert output =~ "Codebase not found"
    end
  end

  describe "resume/1" do
    test "requires valid project path" do
      output = run_resume("/nonexistent/project/12345")

      assert_received {:exit_code, 1}
      assert output =~ "Project not found"
    end

    test "shows header before error" do
      output = run_resume("/nonexistent/project/12345")

      assert output =~ "Albedo"
    end
  end

  describe "replan/2" do
    test "requires valid project path" do
      output = run_replan("/nonexistent/project/12345", [])

      assert_received {:exit_code, 1}
      assert output =~ "Project not found"
    end

    test "shows header and scope info before error" do
      output = run_replan("/nonexistent/project/12345", scope: "partial")

      assert output =~ "Albedo"
    end
  end

  describe "plan/1" do
    test "requires --task option" do
      output = run_plan([])

      assert_received {:exit_code, 1}
      assert output =~ "Missing required --task option"
      assert output =~ "Usage:"
    end

    test "requires --name option when task is provided" do
      output = run_plan(task: "Build an app")

      assert_received {:exit_code, 1}
      assert output =~ "Missing required --name option"
    end

    test "shows header before error" do
      output = run_plan([])

      assert output =~ "Albedo"
    end
  end

  describe "init/0" do
    test "init function is defined" do
      assert function_exported?(Analysis, :init, 0)
    end
  end

  describe "module functions" do
    test "defines expected public functions" do
      assert function_exported?(Analysis, :analyze, 2)
      assert function_exported?(Analysis, :resume, 1)
      assert function_exported?(Analysis, :replan, 2)
      assert function_exported?(Analysis, :plan, 1)
    end
  end
end
