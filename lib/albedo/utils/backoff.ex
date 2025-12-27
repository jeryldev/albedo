defmodule Albedo.Utils.Backoff do
  @moduledoc """
  Exponential backoff with jitter for retry logic.

  Uses the "full jitter" strategy recommended by AWS:
  https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
  """

  @default_base_delay_ms 1000
  @default_max_delay_ms 30_000
  @default_max_retries 3

  @type opts :: [
          base_delay_ms: pos_integer(),
          max_delay_ms: pos_integer(),
          max_retries: non_neg_integer()
        ]

  @doc """
  Executes a function with exponential backoff retry.

  Returns `{:ok, result}` on success or `{:error, reason}` after max retries.

  ## Options
    - `:base_delay_ms` - Initial delay in milliseconds (default: #{@default_base_delay_ms})
    - `:max_delay_ms` - Maximum delay cap (default: #{@default_max_delay_ms})
    - `:max_retries` - Maximum retry attempts (default: #{@default_max_retries})
    - `:retry_on` - Function to determine if error is retryable (default: all errors)
    - `:on_retry` - Callback function called before each retry with (attempt, delay, error)

  ## Examples

      Backoff.with_retry(fn ->
        HTTPClient.get(url)
      end)

      Backoff.with_retry(
        fn -> api_call() end,
        base_delay_ms: 500,
        max_retries: 5,
        retry_on: fn
          {:error, :timeout} -> true
          {:error, {:http_error, status, _}} when status >= 500 -> true
          _ -> false
        end
      )
  """
  @spec with_retry((-> {:ok, any()} | {:error, any()}), opts()) ::
          {:ok, any()} | {:error, any()}
  def with_retry(fun, opts \\ []) do
    config = %{
      base_delay: Keyword.get(opts, :base_delay_ms, @default_base_delay_ms),
      max_delay: Keyword.get(opts, :max_delay_ms, @default_max_delay_ms),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      retry_on: Keyword.get(opts, :retry_on, fn _ -> true end),
      on_retry: Keyword.get(opts, :on_retry)
    }

    do_retry(fun, config, 0, nil)
  end

  defp do_retry(fun, config, attempt, _last_error) when attempt <= config.max_retries do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} = error ->
        if attempt < config.max_retries and config.retry_on.(error) do
          sleep_and_retry(fun, config, attempt, reason, error)
        else
          error
        end
    end
  end

  defp do_retry(_fun, _config, _attempt, last_error) do
    last_error || {:error, :max_retries_exceeded}
  end

  defp sleep_and_retry(fun, config, attempt, reason, error) do
    delay = calculate_delay(attempt, config.base_delay, config.max_delay)
    maybe_call_on_retry(config.on_retry, attempt + 1, delay, reason)
    Process.sleep(delay)
    do_retry(fun, config, attempt + 1, error)
  end

  defp maybe_call_on_retry(nil, _attempt, _delay, _reason), do: :ok

  defp maybe_call_on_retry(callback, attempt, delay, reason),
    do: callback.(attempt, delay, reason)

  @doc """
  Calculates the delay for a given attempt using exponential backoff with full jitter.

  Formula: random(0, min(max_delay, base_delay * 2^attempt))

  ## Examples

      iex> delay = Albedo.Utils.Backoff.calculate_delay(0, 1000, 30000)
      iex> delay >= 0 and delay <= 1000
      true

      iex> delay = Albedo.Utils.Backoff.calculate_delay(3, 1000, 30000)
      iex> delay >= 0 and delay <= 8000
      true
  """
  @spec calculate_delay(non_neg_integer(), pos_integer(), pos_integer()) :: non_neg_integer()
  def calculate_delay(attempt, base_delay_ms, max_delay_ms) do
    exponential_delay = base_delay_ms * Integer.pow(2, attempt)
    capped_delay = min(exponential_delay, max_delay_ms)
    :rand.uniform(capped_delay + 1) - 1
  end

  @doc """
  Returns whether an error is a transient/retryable error for LLM calls.

  Retryable errors:
    - Timeouts
    - Connection errors
    - Server errors (5xx)
    - Rate limiting (with longer backoff)

  Non-retryable errors:
    - Authentication errors (4xx except 429)
    - Invalid request errors
    - Unknown provider
  """
  @spec retryable_llm_error?({:error, any()}) :: boolean()
  def retryable_llm_error?({:error, :timeout}), do: true
  def retryable_llm_error?({:error, :rate_limited}), do: true
  def retryable_llm_error?({:error, {:request_failed, _}}), do: true
  def retryable_llm_error?({:error, {:http_error, status, _}}) when status >= 500, do: true
  def retryable_llm_error?({:error, {:http_error, status}}) when status >= 500, do: true
  def retryable_llm_error?({:error, {:http_error, 429, _}}), do: true
  def retryable_llm_error?({:error, {:http_error, 429}}), do: true
  def retryable_llm_error?(_), do: false
end
