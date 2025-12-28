defmodule Albedo.CLI.Commands.MiscTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Albedo.CLI.Commands.Misc

  setup do
    Application.put_env(:albedo, :test_mode, true)

    on_exit(fn ->
      Application.delete_env(:albedo, :test_mode)
    end)

    :ok
  end

  defp run_show(project_id) do
    capture_io(fn ->
      try do
        Misc.show(project_id)
      catch
        :throw, {:cli_halt, code} -> send(self(), {:exit_code, code})
      end
    end)
  end

  defp run_path(project_id) do
    {stdout, stderr} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        capture_io(fn ->
          try do
            Misc.path(project_id)
          catch
            :throw, {:cli_halt, code} -> send(self(), {:exit_code, code})
          end
        end)
      end)

    {stdout, stderr}
  end

  describe "show/1" do
    test "shows error for nonexistent project" do
      output = run_show("nonexistent-project-12345")

      assert_received {:exit_code, 1}
      assert output =~ "Project not found"
      assert output =~ "nonexistent-project-12345"
    end

    test "shows header before error" do
      output = run_show("nonexistent-project-12345")

      assert output =~ "Albedo"
    end
  end

  describe "path/1" do
    test "shows error for nonexistent project" do
      {_stdout, stderr} = run_path("nonexistent-project-12345")

      assert_received {:exit_code, 1}
      assert stderr =~ "Project not found"
      assert stderr =~ "nonexistent-project-12345"
    end
  end

  describe "module functions" do
    test "show function is callable" do
      Code.ensure_loaded!(Misc)
      assert {:module, Misc} = Code.ensure_loaded(Misc)
    end
  end
end
