defmodule Albedo.LLM.Client do
  @moduledoc """
  Provider-agnostic LLM client with retry logic and fallback support.
  """

  alias Albedo.Config
  alias Albedo.LLM.{Claude, Gemini, OpenAI}

  require Logger

  @max_retries 3
  @base_delay_ms 1000

  @providers %{
    "gemini" => Gemini,
    "claude" => Claude,
    "openai" => OpenAI
  }

  @doc """
  Send a chat request to the configured LLM provider.

  Options:
    - :provider - Override the provider (default: from config)
    - :model - Override the model (default: from config)
    - :temperature - Override temperature (default: from config)
    - :max_tokens - Maximum tokens in response (default: provider-specific)
  """
  def chat(prompt, opts \\ []) do
    config = Config.load!()
    provider = opts[:provider] || Config.get(config, ["llm", "provider"])

    case do_chat_with_retry(config, provider, prompt, opts, 0) do
      {:ok, response} ->
        {:ok, response}

      {:error, :rate_limited} ->
        Logger.warning("Primary provider rate limited, trying fallback")
        try_fallback(config, prompt, opts)

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

  defp do_chat_with_retry(config, provider, prompt, opts, attempt) when attempt < @max_retries do
    provider_module = @providers[provider]

    if provider_module do
      api_key = Config.api_key(config, provider)
      model = opts[:model] || Config.model(config, provider)
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
          delay = @base_delay_ms * :math.pow(2, attempt)
          Logger.warning("Rate limited, retrying in #{trunc(delay)}ms (attempt #{attempt + 1})")
          Process.sleep(trunc(delay))
          do_chat_with_retry(config, provider, prompt, opts, attempt + 1)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:unknown_provider, provider}}
    end
  end

  defp do_chat_with_retry(_config, _provider, _prompt, _opts, _attempt) do
    {:error, :max_retries_exceeded}
  end

  defp try_fallback(config, prompt, opts) do
    fallback_provider = Config.get(config, ["llm", "fallback", "provider"])

    if fallback_provider do
      Logger.info("Trying fallback provider: #{fallback_provider}")
      do_chat_with_retry(config, fallback_provider, prompt, opts, 0)
    else
      {:error, :no_fallback_configured}
    end
  end

  @doc """
  Check if a provider is available (has API key configured).
  """
  def provider_available?(provider) do
    config = Config.load!()
    api_key = Config.api_key(config, provider)
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
