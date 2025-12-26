defmodule Albedo.Config do
  @moduledoc """
  Configuration management for Albedo.

  Single source of truth:
  - Provider: ~/.albedo/config.toml
  - API keys: Environment variables in shell profile
  """

  @default_config %{
    "llm" => %{
      "provider" => "gemini",
      "temperature" => 0.3
    },
    "output" => %{
      "projects_dir" => "~/.albedo/projects"
    },
    "search" => %{
      "tool" => "ripgrep",
      "max_results_per_pattern" => 50,
      "exclude_patterns" => [
        "node_modules",
        "_build",
        "deps",
        ".git",
        "priv/static"
      ]
    },
    "agents" => %{
      "timeout" => 300
    }
  }

  @providers %{
    "gemini" => %{env_var: "GEMINI_API_KEY", model: "gemini-2.0-flash"},
    "claude" => %{env_var: "ANTHROPIC_API_KEY", model: "claude-sonnet-4-20250514"},
    "openai" => %{env_var: "OPENAI_API_KEY", model: "gpt-4o"}
  }

  @config_dir Path.expand("~/.albedo")
  @config_file Path.join(@config_dir, "config.toml")

  def config_dir, do: @config_dir
  def config_file, do: @config_file
  def sessions_dir, do: Path.join(@config_dir, "sessions")
  def projects_dir, do: Path.join(@config_dir, "projects")

  def valid_providers, do: Map.keys(@providers)

  @doc """
  Load configuration from file or return defaults.
  """
  def load do
    case File.read(@config_file) do
      {:ok, content} ->
        case Toml.decode(content) do
          {:ok, config} -> {:ok, deep_merge(@default_config, config)}
          {:error, reason} -> {:error, {:parse_error, reason}}
        end

      {:error, :enoent} ->
        {:ok, @default_config}

      {:error, reason} ->
        {:error, {:read_error, reason}}
    end
  end

  @doc """
  Load configuration, raising on error.
  """
  def load! do
    case load() do
      {:ok, config} -> config
      {:error, reason} -> raise Albedo.Errors.ConfigError, reason: reason
    end
  end

  @doc """
  Get a nested configuration value.
  """
  def get(config, keys) when is_list(keys) do
    get_in(config, keys)
  end

  def get(config, key) when is_binary(key) do
    config[key]
  end

  @doc """
  Get the current LLM provider from config.toml.
  """
  def provider(config) do
    get(config, ["llm", "provider"]) || "gemini"
  end

  @doc """
  Get the environment variable name for a provider.
  """
  def env_var_for_provider(provider) do
    case @providers[provider] do
      %{env_var: env_var} -> env_var
      nil -> "GEMINI_API_KEY"
    end
  end

  @doc """
  Get the API key for the current provider from environment variables.
  """
  def api_key(config) do
    provider = provider(config)
    api_key_for_provider(provider)
  end

  @doc """
  Get the API key for a specific provider from environment variables.
  """
  def api_key_for_provider(provider) do
    env_var = env_var_for_provider(provider)
    System.get_env(env_var)
  end

  @doc """
  Get the model for the current provider.
  """
  def model(config) do
    provider = provider(config)

    case @providers[provider] do
      %{model: model} -> model
      nil -> "gemini-2.0-flash"
    end
  end

  @doc """
  Get the temperature setting.
  """
  def temperature(config) do
    get(config, ["llm", "temperature"]) || 0.3
  end

  @doc """
  Get the session directory, expanded.
  Deprecated: Use projects_dir/1 instead.
  """
  def session_dir(config) do
    dir = get(config, ["output", "session_dir"]) || "~/.albedo/sessions"
    Path.expand(dir)
  end

  @doc """
  Get the projects directory, expanded.
  """
  def projects_dir(config) do
    dir =
      get(config, ["output", "projects_dir"]) || get(config, ["output", "session_dir"]) ||
        "~/.albedo/projects"

    Path.expand(dir)
  end

  @doc """
  Get search exclude patterns.
  """
  def exclude_patterns(config) do
    get(config, ["search", "exclude_patterns"]) || []
  end

  @doc """
  Get agent timeout in seconds.
  """
  def agent_timeout(config) do
    get(config, ["agents", "timeout"]) || 300
  end

  @doc """
  Initialize configuration directory and default config file.
  """
  def init do
    with :ok <- ensure_dir(@config_dir),
         :ok <- ensure_dir(projects_dir()),
         :ok <- ensure_dir(sessions_dir()),
         :ok <- write_default_config() do
      {:ok, @config_file}
    end
  end

  @doc """
  Update the provider in config.toml.
  """
  def set_provider(provider) when provider in ["gemini", "claude", "openai"] do
    case File.read(@config_file) do
      {:ok, content} ->
        updated = update_provider_in_toml(content, provider)
        File.write(@config_file, updated)

      {:error, :enoent} ->
        content = generate_config_toml(provider)
        File.mkdir_p!(@config_dir)
        File.write(@config_file, content)
    end
  end

  def set_provider(_provider), do: {:error, :invalid_provider}

  defp update_provider_in_toml(content, provider) do
    if Regex.match?(~r/^provider\s*=\s*"[^"]*"/m, content) do
      Regex.replace(~r/^provider\s*=\s*"[^"]*"/m, content, "provider = \"#{provider}\"")
    else
      content <> "\n[llm]\nprovider = \"#{provider}\"\n"
    end
  end

  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_error, dir, reason}}
    end
  end

  defp write_default_config do
    if File.exists?(@config_file) do
      :ok
    else
      content = generate_config_toml("gemini")
      File.write(@config_file, content)
    end
  end

  defp generate_config_toml(provider) do
    """
    # Albedo Configuration
    # Generated on #{Date.utc_today()}

    [llm]
    provider = "#{provider}"  # gemini | claude | openai
    temperature = 0.3  # Lower = more deterministic

    [output]
    projects_dir = "~/.albedo/projects"

    [search]
    tool = "ripgrep"
    max_results_per_pattern = 50
    exclude_patterns = [
      "node_modules",
      "_build",
      "deps",
      ".git",
      "priv/static"
    ]

    [agents]
    timeout = 300  # Timeout for each agent in seconds
    """
  end

  defp deep_merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn
      _key, base_val, override_val when is_map(base_val) and is_map(override_val) ->
        deep_merge(base_val, override_val)

      _key, _base_val, override_val ->
        override_val
    end)
  end

  defp deep_merge(_base, override), do: override
end
