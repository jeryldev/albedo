defmodule Albedo.CLI.Commands.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Albedo.CLI.Commands.Config

  setup do
    Application.put_env(:albedo, :test_mode, true)

    on_exit(fn ->
      Application.delete_env(:albedo, :test_mode)
    end)

    :ok
  end

  defp run_command(args) do
    capture_io(fn ->
      try do
        Config.dispatch(args)
      catch
        :throw, {:cli_halt, code} -> send(self(), {:exit_code, code})
      end
    end)
  end

  describe "dispatch/1 help" do
    test "shows help with help subcommand" do
      output = run_command(["help"])
      assert output =~ "albedo config"
      assert output =~ "USAGE:"
      assert output =~ "SUBCOMMANDS:"
      assert output =~ "show"
      assert output =~ "set-provider"
      assert output =~ "set-key"
    end

    test "help includes examples" do
      output = run_command(["help"])
      assert output =~ "EXAMPLES:"
      assert output =~ "albedo config show"
      assert output =~ "albedo config set-provider"
    end

    test "help includes configuration files section" do
      output = run_command(["help"])
      assert output =~ "CONFIGURATION FILES:"
      assert output =~ "config.toml"
      assert output =~ "projects"
    end

    test "help includes supported providers" do
      output = run_command(["help"])
      assert output =~ "SUPPORTED PROVIDERS:"
      assert output =~ "gemini"
      assert output =~ "claude"
      assert output =~ "openai"
    end
  end

  describe "dispatch/1 show" do
    test "shows current configuration" do
      output = run_command(["show"])
      assert output =~ "Albedo"
      assert output =~ "Current Configuration:"
      assert output =~ "Provider:"
      assert output =~ "Model:"
      assert output =~ "API Key:"
    end

    test "defaults to show when no subcommand given" do
      output = run_command([])
      assert output =~ "Current Configuration:"
      assert output =~ "Provider:"
    end

    test "shows config and projects paths" do
      output = run_command(["show"])
      assert output =~ "Config:"
      assert output =~ "Projects:"
    end
  end

  describe "dispatch/1 unknown subcommand" do
    test "reports unknown subcommand" do
      output = run_command(["unknown-subcommand"])

      assert_received {:exit_code, 1}
      assert output =~ "Unknown config subcommand"
      assert output =~ "unknown-subcommand"
    end

    test "shows help after unknown subcommand error" do
      output = run_command(["unknown-subcommand"])

      assert output =~ "SUBCOMMANDS:"
      assert output =~ "show"
    end
  end

  describe "help/0" do
    test "returns comprehensive help text" do
      output = capture_io(fn -> Config.help() end)

      assert output =~ "albedo config"
      assert output =~ "show"
      assert output =~ "set-provider"
      assert output =~ "set-key"
      assert output =~ "gemini"
      assert output =~ "claude"
      assert output =~ "openai"
    end
  end
end
