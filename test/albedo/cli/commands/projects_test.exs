defmodule Albedo.CLI.Commands.ProjectsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Albedo.CLI.Commands.Projects
  alias Albedo.Config

  setup do
    # Ensure we're in test mode
    Application.put_env(:albedo, :test_mode, true)

    on_exit(fn ->
      Application.delete_env(:albedo, :test_mode)
    end)

    :ok
  end

  defp run_command(args, opts \\ []) do
    capture_io(fn ->
      try do
        Projects.dispatch(args, opts)
      catch
        :throw, {:cli_halt, code} -> send(self(), {:exit_code, code})
      end
    end)
  end

  describe "dispatch/2 help" do
    test "shows help with help subcommand" do
      output = run_command(["help"])
      assert output =~ "albedo projects"
      assert output =~ "USAGE:"
      assert output =~ "SUBCOMMANDS:"
      assert output =~ "list"
      assert output =~ "create"
      assert output =~ "rename"
      assert output =~ "delete"
    end

    test "shows help with --help option" do
      output = run_command([], help: true)
      assert output =~ "albedo projects"
      assert output =~ "SUBCOMMANDS:"
    end

    test "help includes examples" do
      output = run_command(["help"])
      assert output =~ "EXAMPLES:"
      assert output =~ "albedo projects list"
      assert output =~ "albedo projects create"
    end

    test "help includes project structure info" do
      output = run_command(["help"])
      assert output =~ "PROJECT STRUCTURE:"
      assert output =~ "project.json"
      assert output =~ "tickets.json"
    end
  end

  describe "dispatch/2 list" do
    test "lists projects or shows empty message" do
      output = run_command([])
      # Should show either projects or "No projects found"
      assert output =~ "Albedo" or output =~ "No projects" or output =~ "Recent projects"
    end

    test "list subcommand works" do
      output = run_command(["list"])
      assert output =~ "Albedo" or output =~ "No projects" or output =~ "Recent projects"
    end
  end

  describe "dispatch/2 create" do
    test "create requires task description" do
      output = run_command(["create"])

      assert_received {:exit_code, 1}
      assert output =~ "Missing task description"
    end

    test "create with --task option works" do
      output = run_command(["create"], task: "Test task")
      # Should attempt to create project
      assert output =~ "Albedo"
    end

    test "create with positional argument works" do
      output = run_command(["create", "Test task"])
      # Should attempt to create project
      assert output =~ "Albedo"
    end
  end

  describe "dispatch/2 rename" do
    test "rename requires project_id and new_name" do
      output = run_command(["rename"])

      assert_received {:exit_code, 1}
      assert output =~ "Missing project ID and new name"
    end

    test "rename requires new_name when project_id given" do
      output = run_command(["rename", "some-project"])

      assert_received {:exit_code, 1}
      assert output =~ "Missing new name"
    end

    test "rename with nonexistent project shows error" do
      output = run_command(["rename", "nonexistent-project-12345", "new-name"])

      assert_received {:exit_code, 1}
      assert output =~ "not found" or output =~ "Failed"
    end
  end

  describe "dispatch/2 delete" do
    test "delete requires project_id" do
      output = run_command(["delete"])

      assert_received {:exit_code, 1}
      assert output =~ "Missing project ID"
    end

    test "delete with --yes skips confirmation for nonexistent project" do
      output = run_command(["delete", "nonexistent-project-12345"], yes: true)

      assert_received {:exit_code, 1}
      assert output =~ "not found"
    end
  end

  describe "dispatch/2 unknown subcommand" do
    test "reports unknown subcommand" do
      output = run_command(["unknown-subcommand"])

      assert_received {:exit_code, 1}
      assert output =~ "Unknown projects subcommand"
      assert output =~ "unknown-subcommand"
    end
  end

  describe "help/0" do
    test "returns comprehensive help text" do
      output = capture_io(fn -> Projects.help() end)

      assert output =~ "albedo projects"
      assert output =~ "list"
      assert output =~ "create"
      assert output =~ "rename"
      assert output =~ "delete"
      assert output =~ "--task"
      assert output =~ "--yes"
    end
  end

  describe "integration with Config" do
    test "uses projects_dir from config" do
      config = Config.load!()
      projects_dir = Config.projects_dir(config)

      # projects_dir should be a valid path
      assert is_binary(projects_dir)
      assert String.starts_with?(projects_dir, "/")
    end
  end
end
