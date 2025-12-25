defmodule Albedo.LLM.Client do
  @moduledoc """
  Provider-agnostic LLM client with retry logic.
  """

  alias Albedo.Config
  alias Albedo.LLM.{Claude, Gemini, OpenAI}

  require Logger

  @max_retries 2
  @retry_delay_ms 2000

  @providers %{
    "gemini" => Gemini,
    "claude" => Claude,
    "openai" => OpenAI
  }

  @doc """
  Send a chat request to the configured LLM provider.

  Options:
    - :model - Override the model (default: from config)
    - :temperature - Override temperature (default: from config)
    - :max_tokens - Maximum tokens in response (default: provider-specific)
  """
  def chat(prompt, opts \\ []) do
    config = Config.load!()

    case do_chat(config, prompt, opts, 0) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        Logger.error("LLM request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Send a chat request, raising on error.
  """
  def chat!(prompt, opts \\ []) do
    case chat(prompt, opts) do
      {:ok, response} -> response
      {:error, reason} -> raise Albedo.Errors.LLMError, provider: "unknown", reason: reason
    end
  end

  defp do_chat(config, prompt, opts, attempt) when attempt < @max_retries do
    provider = Config.provider(config)
    provider_module = @providers[provider]

    if provider_module do
      api_key = Config.api_key(config)
      model = opts[:model] || Config.model(config)
      temperature = opts[:temperature] || Config.temperature(config)

      request_opts = [
        api_key: api_key,
        model: model,
        temperature: temperature,
        max_tokens: opts[:max_tokens]
      ]

      case provider_module.chat(prompt, request_opts) do
        {:ok, response} ->
          {:ok, response}

        {:error, :rate_limited} ->
          {:error, :rate_limited}

        {:error, :timeout} ->
          retry_with_log(config, prompt, opts, attempt, "Request timed out")

        {:error, {:request_failed, %{reason: :timeout}}} ->
          retry_with_log(config, prompt, opts, attempt, "Connection timed out")

        {:error, {:request_failed, %{reason: :econnrefused}}} ->
          retry_with_log(config, prompt, opts, attempt, "Connection refused")

        {:error, {:request_failed, _}} ->
          retry_with_log(config, prompt, opts, attempt, "Network error")

        {:error, {:http_error, status, _}} when status >= 500 ->
          retry_with_log(config, prompt, opts, attempt, "Server error #{status}")

        {:error, {:http_error, status}} when status >= 500 ->
          retry_with_log(config, prompt, opts, attempt, "Server error #{status}")

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:unknown_provider, provider}}
    end
  end

  defp do_chat(_config, _prompt, _opts, _attempt) do
    {:error, :max_retries_exceeded}
  end

  defp retry_with_log(config, prompt, opts, attempt, message) do
    Logger.warning("#{message}, retrying (attempt #{attempt + 1}/#{@max_retries})")
    Process.sleep(@retry_delay_ms)
    do_chat(config, prompt, opts, attempt + 1)
  end

  @doc """
  Check if a provider is available (has API key configured).
  """
  def provider_available?(provider) do
    api_key = Config.api_key_for_provider(provider)
    api_key != nil && api_key != ""
  end

  @doc """
  List available providers.
  """
  def available_providers do
    Map.keys(@providers)
    |> Enum.filter(&provider_available?/1)
  end
end
