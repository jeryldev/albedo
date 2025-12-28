defmodule Albedo.LLM.Provider do
  @moduledoc """
  Behaviour for LLM providers.

  All LLM providers (Gemini, Claude, OpenAI) implement this behaviour
  to provide a consistent interface for chat completions.

  ## Required Callbacks

  * `chat/2` - Send a chat request and receive a response

  ## Options

  All providers accept the following options:

  * `:api_key` - API key (required)
  * `:model` - Model to use (provider-specific default)
  * `:temperature` - Temperature for response randomness (default: 0.3)
  * `:max_tokens` - Maximum tokens in response (default: 8192)

  ## Example

      defmodule MyProvider do
        @behaviour Albedo.LLM.Provider

        @impl true
        def chat(prompt, opts) do
          # Implementation
          {:ok, "response text"}
        end
      end
  """

  @type prompt :: String.t()
  @type opts :: keyword()
  @type response :: String.t()
  @type error_reason ::
          :missing_api_key
          | :safety_blocked
          | :rate_limited
          | :timeout
          | {:api_error, map()}
          | {:http_error, integer(), term()}
          | {:request_failed, term()}
          | {:unexpected_response, term()}

  @doc """
  Send a chat request to the LLM provider.

  ## Parameters

  * `prompt` - The prompt text to send
  * `opts` - Options including `:api_key`, `:model`, `:temperature`, `:max_tokens`

  ## Returns

  * `{:ok, response}` - Success with the response text
  * `{:error, reason}` - Failure with error reason
  """
  @callback chat(prompt(), opts()) :: {:ok, response()} | {:error, error_reason()}
end
