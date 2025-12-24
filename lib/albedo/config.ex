defmodule Albedo.Config do
  @moduledoc """
  Configuration management for Albedo.
  Loads and manages configuration from ~/.albedo/config.toml
  """

  @default_config %{
    "llm" => %{
      "provider" => "gemini",
      "api_key_env" => "GEMINI_API_KEY",
      "model" => "gemini-2.0-flash",
      "temperature" => 0.3,
      "fallback" => %{
        "provider" => "claude",
        "api_key_env" => "ANTHROPIC_API_KEY",
        "model" => "claude-sonnet-4-20250514"
      }
    },
    "output" => %{
      "default_format" => "markdown",
      "session_dir" => "~/.albedo/sessions"
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
      "timeout" => 300,
      "max_parallel" => 5
    }
  }

  @config_dir Path.expand("~/.albedo")
  @config_file Path.join(@config_dir, "config.toml")

  def config_dir, do: @config_dir
  def config_file, do: @config_file
  def sessions_dir, do: Path.join(@config_dir, "sessions")

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
  Get the API key for a provider from environment variables.
  """
  def api_key(config, provider \\ nil) do
    provider = provider || get(config, ["llm", "provider"])
    env_var = get_api_key_env(config, provider)
    System.get_env(env_var)
  end

  defp get_api_key_env(config, provider) do
    primary_provider = get(config, ["llm", "provider"])

    if provider == primary_provider do
      get(config, ["llm", "api_key_env"])
    else
      get(config, ["llm", "fallback", "api_key_env"])
    end
  end

  @doc """
  Get the model for a provider.
  """
  def model(config, provider \\ nil) do
    provider = provider || get(config, ["llm", "provider"])
    primary_provider = get(config, ["llm", "provider"])

    if provider == primary_provider do
      get(config, ["llm", "model"])
    else
      get(config, ["llm", "fallback", "model"])
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
  """
  def session_dir(config) do
    dir = get(config, ["output", "session_dir"]) || "~/.albedo/sessions"
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
         :ok <- ensure_dir(sessions_dir()),
         :ok <- write_default_config() do
      {:ok, @config_file}
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
      content = generate_default_config_toml()
      File.write(@config_file, content)
    end
  end

  defp generate_default_config_toml do
    """
    # Albedo Configuration
    # Generated on #{Date.utc_today()}

    [llm]
    provider = "gemini"  # gemini | claude | openai
    api_key_env = "GEMINI_API_KEY"  # Environment variable name
    model = "gemini-2.0-flash"  # Model to use
    temperature = 0.3  # Lower = more deterministic

    [llm.fallback]
    provider = "claude"
    api_key_env = "ANTHROPIC_API_KEY"
    model = "claude-sonnet-4-20250514"

    [output]
    default_format = "markdown"  # markdown | linear | jira
    session_dir = "~/.albedo/sessions"

    [search]
    tool = "ripgrep"  # ripgrep | grep | native
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
    max_parallel = 5  # Maximum parallel agents
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
