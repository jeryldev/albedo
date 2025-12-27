defmodule Albedo.CLI.Commands.Config do
  @moduledoc """
  CLI commands for managing Albedo configuration.
  Handles show, set-provider, and set-key operations.
  """

  alias Albedo.CLI.Output
  alias Albedo.Config

  def dispatch([]) do
    dispatch(["show"])
  end

  def dispatch(["help" | _]), do: help()

  def dispatch(["show" | _]) do
    Output.print_header()
    config = Config.load!()

    provider = Config.provider(config)
    api_key = Config.api_key(config)
    model = Config.model(config)

    Owl.IO.puts(Owl.Data.tag("Current Configuration:", :cyan))
    IO.puts("")

    IO.puts("  Provider:   #{provider}")
    IO.puts("  Model:      #{model}")

    if api_key do
      masked = Output.mask_api_key(api_key)
      Owl.IO.puts(["  API Key:    ", Owl.Data.tag(masked, :green)])
    else
      Owl.IO.puts(["  API Key:    ", Owl.Data.tag("NOT SET", :red)])
    end

    IO.puts("")
    IO.puts("  Config:     #{Config.config_file()}")
    IO.puts("  Projects:   #{Config.projects_dir()}")
  end

  def dispatch(["set-provider" | _]) do
    Output.print_header()

    IO.puts("Select LLM provider:")
    IO.puts("")
    IO.puts("  1. Gemini (recommended - free tier available)")
    IO.puts("  2. Claude")
    IO.puts("  3. OpenAI")
    IO.puts("")

    choice = safe_gets("Enter choice [1]: ")

    provider =
      case choice do
        "2" -> "claude"
        "3" -> "openai"
        _ -> "gemini"
      end

    env_var = Config.env_var_for_provider(provider)

    IO.puts("")
    IO.puts("This will update #{Config.config_file()}:")
    Owl.IO.puts(Owl.Data.tag("  provider = \"#{provider}\"", :cyan))
    IO.puts("")

    confirm = safe_gets("Proceed? [Y/n]: ") |> String.downcase()

    if confirm in ["", "y", "yes"] do
      case Config.set_provider(provider) do
        :ok ->
          Output.print_success("Provider set to #{provider}")
          IO.puts("")
          Output.print_info("Make sure you have #{env_var} set in your shell profile.")
          Output.print_info("Run: albedo config set-key")

        {:error, reason} ->
          Output.print_error("Failed to update config: #{inspect(reason)}")
          halt_with_error(1)
      end
    else
      Output.print_info("Cancelled.")
    end
  end

  def dispatch(["set-key" | _]) do
    Output.print_header()

    config = Config.load!()
    provider = Config.provider(config)
    env_var = Config.env_var_for_provider(provider)

    IO.puts("Current provider: #{provider}")
    IO.puts("Environment variable: #{env_var}")
    IO.puts("")

    api_key = safe_gets("Enter your API key: ")

    if api_key == "" do
      Output.print_info("Cancelled.")
    else
      shell_profile = detect_shell_profile()
      masked = Output.mask_api_key(api_key)
      export_line = "export #{env_var}=\"#{api_key}\""

      IO.puts("")
      IO.puts("This will update #{shell_profile}:")
      Owl.IO.puts(Owl.Data.tag("  export #{env_var}=\"#{masked}\"", :cyan))
      IO.puts("")

      confirm = safe_gets("Proceed? [Y/n]: ") |> String.downcase()
      handle_set_key_confirm(confirm, shell_profile, env_var, export_line)
    end
  end

  def dispatch([unknown | _]) do
    Output.print_error("Unknown config subcommand: #{unknown}")
    IO.puts("")
    help()
    halt_with_error(1)
  end

  def help do
    Owl.IO.puts([
      Owl.Data.tag("albedo config", :cyan),
      " - Manage configuration\n\n",
      Owl.Data.tag("USAGE:", :yellow),
      "\n    albedo config [subcommand]\n\n",
      Owl.Data.tag("SUBCOMMANDS:", :yellow),
      """

          show                    Show current configuration (default)
          set-provider            Select LLM provider interactively
          set-key                 Set API key for current provider
          help                    Show this help message

      """,
      Owl.Data.tag("EXAMPLES:", :yellow),
      """

          # Show current configuration
          albedo config
          albedo config show

          # Change LLM provider (interactive)
          albedo config set-provider

          # Set API key (interactive)
          albedo config set-key

      """,
      Owl.Data.tag("CONFIGURATION FILES:", :yellow),
      """

          ~/.albedo/config.toml     Configuration file
          ~/.albedo/projects/       Project storage directory

      """,
      Owl.Data.tag("SUPPORTED PROVIDERS:", :yellow),
      """

          gemini      Google Gemini (default, free tier available)
          claude      Anthropic Claude
          openai      OpenAI GPT
      """
    ])
  end

  defp handle_set_key_confirm(confirm, shell_profile, env_var, export_line)
       when confirm in ["", "y", "yes"] do
    case append_to_shell_profile(shell_profile, env_var, export_line) do
      {:ok, :replaced} -> print_shell_update_success("Replaced", env_var, shell_profile)
      {:ok, :added} -> print_shell_update_success("Added", env_var, shell_profile)
    end
  end

  defp handle_set_key_confirm(_, _, _, _) do
    Output.print_info("Cancelled.")
  end

  defp print_shell_update_success(action, env_var, shell_profile) do
    Output.print_success("#{action} #{env_var} in #{shell_profile}")
    IO.puts("")
    Output.print_info("Run: source #{shell_profile}")
  end

  defp detect_shell_profile do
    shell = System.get_env("SHELL") || ""

    cond do
      String.contains?(shell, "zsh") -> "~/.zshrc"
      String.contains?(shell, "bash") -> "~/.bashrc"
      true -> "~/.profile"
    end
  end

  defp append_to_shell_profile(shell_profile, env_var, export_line) do
    path = Path.expand(shell_profile)

    if File.exists?(path) do
      content = File.read!(path)
      pattern = ~r/^export #{Regex.escape(env_var)}=.*$/m

      if Regex.match?(pattern, content) do
        updated = Regex.replace(pattern, content, export_line)
        File.write!(path, updated)
        {:ok, :replaced}
      else
        File.write!(path, content <> "\n# Added by Albedo\n#{export_line}\n")
        {:ok, :added}
      end
    else
      File.write!(path, "# Added by Albedo\n#{export_line}\n")
      {:ok, :added}
    end
  end

  @spec halt_with_error(non_neg_integer()) :: no_return()
  defp halt_with_error(code) do
    if Application.get_env(:albedo, :test_mode, false) do
      throw({:cli_halt, code})
    else
      System.halt(code)
    end
  end

  defp safe_gets(prompt) do
    case IO.gets(prompt) do
      :eof -> ""
      {:error, _} -> ""
      result when is_binary(result) -> String.trim(result)
    end
  end
end
