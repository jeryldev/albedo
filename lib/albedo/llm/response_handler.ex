defmodule Albedo.LLM.ResponseHandler do
  @moduledoc """
  Shared HTTP response handling for LLM API clients.
  Reduces duplication across Gemini, Claude, and OpenAI providers.
  """

  require Logger

  @doc """
  Handles common HTTP response patterns for LLM API calls.
  Returns standardized error tuples for common status codes.

  Provider-specific parsing should be done by passing a parser function
  for successful (200) responses.

  ## Examples

      handle_response({:ok, %{status: 200, body: body}}, &parse_gemini/1, "Gemini")
      handle_response({:ok, %{status: 429}}, nil, "Claude")
  """
  @spec handle_response(
          {:ok, Req.Response.t()} | {:error, term()},
          (map() -> {:ok, String.t()} | {:error, term()}),
          String.t()
        ) :: {:ok, String.t()} | {:error, term()}
  def handle_response({:ok, %{status: 200, body: body}}, parser, _provider)
      when is_function(parser) do
    parser.(body)
  end

  def handle_response({:ok, %{status: 429}}, _parser, _provider), do: {:error, :rate_limited}
  def handle_response({:ok, %{status: 401}}, _parser, _provider), do: {:error, :invalid_api_key}
  def handle_response({:ok, %{status: 403}}, _parser, _provider), do: {:error, :forbidden}
  def handle_response({:ok, %{status: 529}}, _parser, _provider), do: {:error, :overloaded}

  def handle_response({:ok, %{status: 400, body: body}}, _parser, provider) do
    Logger.error("#{provider} bad request: #{inspect(body)}")
    {:error, {:bad_request, body}}
  end

  def handle_response({:ok, %{status: status, body: body}}, _parser, provider) do
    Logger.error("#{provider} error (#{status}): #{inspect(body)}")
    {:error, {:http_error, status, body}}
  end

  def handle_response({:error, reason}, _parser, provider) do
    Logger.error("#{provider} request failed: #{inspect(reason)}")
    {:error, {:request_failed, reason}}
  end
end
