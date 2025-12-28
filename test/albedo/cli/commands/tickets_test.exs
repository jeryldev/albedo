defmodule Albedo.CLI.Commands.TicketsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Albedo.CLI.Commands.Tickets

  setup do
    Application.put_env(:albedo, :test_mode, true)

    on_exit(fn ->
      Application.delete_env(:albedo, :test_mode)
    end)

    :ok
  end

  defp run_command(args, opts \\ []) do
    capture_io(fn ->
      try do
        Tickets.dispatch(args, opts)
      catch
        :throw, {:cli_halt, code} -> send(self(), {:exit_code, code})
      end
    end)
  end

  describe "dispatch/2 help" do
    test "shows help with help subcommand" do
      output = run_command(["help"])
      assert output =~ "albedo tickets"
      assert output =~ "USAGE:"
      assert output =~ "SUBCOMMANDS:"
      assert output =~ "list"
      assert output =~ "show"
      assert output =~ "add"
      assert output =~ "edit"
      assert output =~ "delete"
      assert output =~ "start"
      assert output =~ "done"
      assert output =~ "reset"
      assert output =~ "export"
    end

    test "shows help with --help option" do
      output = run_command([], help: true)
      assert output =~ "albedo tickets"
      assert output =~ "SUBCOMMANDS:"
    end

    test "help includes options section" do
      output = run_command(["help"])
      assert output =~ "OPTIONS:"
      assert output =~ "-P, --project"
      assert output =~ "--status"
      assert output =~ "--json"
    end

    test "help includes add options" do
      output = run_command(["help"])
      assert output =~ "ADD OPTIONS:"
      assert output =~ "--title"
      assert output =~ "--description"
      assert output =~ "--priority"
      assert output =~ "--points"
    end

    test "help includes edit options" do
      output = run_command(["help"])
      assert output =~ "EDIT OPTIONS:"
    end

    test "help includes export options" do
      output = run_command(["help"])
      assert output =~ "EXPORT OPTIONS:"
      assert output =~ "--format"
      assert output =~ "json"
      assert output =~ "csv"
      assert output =~ "markdown"
      assert output =~ "github"
    end

    test "help includes examples" do
      output = run_command(["help"])
      assert output =~ "EXAMPLES:"
      assert output =~ "albedo tickets"
      assert output =~ "albedo tickets show 1"
      assert output =~ "albedo tickets add"
    end

    test "help includes ticket statuses" do
      output = run_command(["help"])
      assert output =~ "TICKET STATUSES:"
      assert output =~ "pending"
      assert output =~ "in_progress"
      assert output =~ "completed"
    end

    test "help includes ticket types" do
      output = run_command(["help"])
      assert output =~ "TICKET TYPES:"
      assert output =~ "feature"
      assert output =~ "bugfix"
      assert output =~ "chore"
      assert output =~ "docs"
      assert output =~ "test"
    end
  end

  describe "dispatch/2 list" do
    test "defaults to list when no subcommand given" do
      output = run_command([])
      # Will attempt to list - may succeed or fail based on project availability
      assert output =~ "Albedo" or output =~ "No projects" or output =~ "tickets" or
               output =~ "No project selected"
    end
  end

  describe "dispatch/2 add" do
    test "add requires title" do
      output = run_command(["add"])

      assert_received {:exit_code, 1}
      assert output =~ "Title is required"
    end

    test "add shows usage when title missing" do
      output = run_command(["add"])

      assert output =~ "Usage:"
      assert output =~ "albedo tickets add"
    end
  end

  describe "dispatch/2 delete" do
    test "delete requires ticket ID" do
      output = run_command(["delete"])

      assert_received {:exit_code, 1}
      assert output =~ "No ticket ID specified"
    end

    test "delete shows usage when ID missing" do
      output = run_command(["delete"])

      assert output =~ "Usage:"
      assert output =~ "albedo tickets delete"
    end
  end

  describe "dispatch/2 unknown subcommand" do
    test "reports unknown subcommand" do
      output = run_command(["unknown-subcommand"])

      assert_received {:exit_code, 1}
      assert output =~ "Unknown tickets subcommand"
      assert output =~ "unknown-subcommand"
    end
  end

  describe "export format parsing" do
    test "help shows supported export formats" do
      output = run_command(["help"])
      assert output =~ "json"
      assert output =~ "csv"
      assert output =~ "markdown"
      assert output =~ "github"
    end
  end

  describe "help/0" do
    test "returns comprehensive help text" do
      output = capture_io(fn -> Tickets.help() end)

      assert output =~ "albedo tickets"
      assert output =~ "list"
      assert output =~ "show"
      assert output =~ "add"
      assert output =~ "edit"
      assert output =~ "delete"
      assert output =~ "start"
      assert output =~ "done"
      assert output =~ "reset"
      assert output =~ "export"
    end
  end
end
