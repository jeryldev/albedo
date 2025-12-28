defmodule Albedo.LLM.Client do
  @moduledoc """
  Provider-agnostic LLM client with exponential backoff retry.
  """

  alias Albedo.Config
  alias Albedo.LLM.{Claude, Gemini, OpenAI}
  alias Albedo.Utils.Backoff

  require Logger

  @providers %{
    "gemini" => Gemini,
    "claude" => Claude,
    "openai" => OpenAI
  }

  @retry_opts [
    base_delay_ms: 1000,
    max_delay_ms: 30_000,
    max_retries: 3
  ]

  @doc """
  Send a chat request to the configured LLM provider.

  Options:
    - :model - Override the model (default: from config)
    - :temperature - Override temperature (default: from config)
    - :max_tokens - Maximum tokens in response (default: provider-specific)
  """
  def chat(prompt, opts \\ []) do
    config = Config.load!()
    provider = Config.provider(config)
    provider_module = @providers[provider]

    if provider_module do
      do_chat_with_backoff(config, prompt, opts, provider_module)
    else
      {:error, {:unknown_provider, provider}}
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

  defp do_chat_with_backoff(config, prompt, opts, provider_module) do
    retry_opts =
      @retry_opts
      |> Keyword.put(:retry_on, &Backoff.retryable_llm_error?/1)
      |> Keyword.put(:on_retry, &log_retry/3)

    Backoff.with_retry(
      fn ->
        execute_provider_chat(config, prompt, opts, provider_module)
      end,
      retry_opts
    )
  end

  defp execute_provider_chat(config, prompt, opts, provider_module) do
    provider = Config.provider(config)
    model = opts[:model] || Config.model(config)
    prompt_length = String.length(prompt)

    Logger.debug("LLM request starting",
      provider: provider,
      model: model,
      prompt_length: prompt_length
    )

    request_opts = [
      api_key: Config.api_key(config),
      model: model,
      temperature: opts[:temperature] || Config.temperature(config),
      max_tokens: opts[:max_tokens]
    ]

    start_time = System.monotonic_time(:millisecond)
    result = provider_module.chat(prompt, request_opts)
    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, response} ->
        Logger.debug("LLM request completed",
          provider: provider,
          model: model,
          duration_ms: duration_ms,
          response_length: String.length(response)
        )

      {:error, reason} ->
        Logger.debug("LLM request failed",
          provider: provider,
          model: model,
          duration_ms: duration_ms,
          error: inspect(reason)
        )
    end

    result
  end

  defp log_retry(attempt, delay_ms, reason) do
    Logger.warning(
      "LLM request failed: #{format_error(reason)}, " <>
        "retrying in #{delay_ms}ms (attempt #{attempt}/#{@retry_opts[:max_retries]})"
    )
  end

  defp format_error(:timeout), do: "timeout"
  defp format_error(:rate_limited), do: "rate limited"
  defp format_error({:request_failed, %{reason: reason}}), do: "connection error: #{reason}"
  defp format_error({:request_failed, _}), do: "network error"
  defp format_error({:http_error, status, _}), do: "HTTP #{status}"
  defp format_error({:http_error, status}), do: "HTTP #{status}"
  defp format_error(reason), do: inspect(reason)

  @doc """
  Check if a provider is available (has API key configured).
  """
  def provider_available?(provider) do
    api_key = Config.api_key_for_provider(provider)
    api_key != nil and api_key != ""
  end

  @doc """
  List available providers.
  """
  def available_providers do
    Map.keys(@providers)
    |> Enum.filter(&provider_available?/1)
  end
end
