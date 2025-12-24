defmodule Albedo.LLM.Claude do
  @moduledoc """
  Anthropic Claude API client.
  """

  require Logger

  @base_url "https://api.anthropic.com/v1"
  @default_model "claude-sonnet-4-20250514"
  @default_max_tokens 8192
  @api_version "2023-06-01"

  @doc """
  Send a chat request to Claude.

  Options:
    - :api_key - API key (required)
    - :model - Model to use (default: claude-sonnet-4-20250514)
    - :temperature - Temperature (default: 0.3)
    - :max_tokens - Maximum tokens (default: 8192)
  """
  def chat(prompt, opts \\ []) do
    api_key = opts[:api_key]
    model = opts[:model] || @default_model
    temperature = opts[:temperature] || 0.3
    max_tokens = opts[:max_tokens] || @default_max_tokens

    if api_key do
      url = "#{@base_url}/messages"

      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", @api_version},
        {"content-type", "application/json"}
      ]

      body = %{
        "model" => model,
        "max_tokens" => max_tokens,
        "temperature" => temperature,
        "messages" => [
          %{
            "role" => "user",
            "content" => prompt
          }
        ]
      }

      # Long timeout for LLM requests (10 minutes)
      case Req.post(url, json: body, headers: headers, receive_timeout: 600_000, retry: false) do
        {:ok, %{status: 200, body: response_body}} ->
          parse_response(response_body)

        {:ok, %{status: 429}} ->
          {:error, :rate_limited}

        {:ok, %{status: 400, body: body}} ->
          Logger.error("Claude bad request: #{inspect(body)}")
          {:error, {:bad_request, body}}

        {:ok, %{status: 401}} ->
          {:error, :invalid_api_key}

        {:ok, %{status: 403}} ->
          {:error, :forbidden}

        {:ok, %{status: 529}} ->
          {:error, :overloaded}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Claude error (#{status}): #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.error("Claude request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    else
      {:error, :missing_api_key}
    end
  end

  defp parse_response(body) do
    case body do
      %{"content" => content} when is_list(content) ->
        text =
          content
          |> Enum.filter(&(&1["type"] == "text"))
          |> Enum.map_join("", & &1["text"])

        {:ok, text}

      %{"error" => error} ->
        {:error, {:api_error, error}}

      _ ->
        {:error, {:unexpected_response, body}}
    end
  end

  @doc """
  Check if the API key is valid by making a simple request.
  """
  def validate_api_key(api_key) do
    case chat("Say 'ok'", api_key: api_key, max_tokens: 10) do
      {:ok, _} -> :ok
      {:error, :invalid_api_key} -> {:error, :invalid}
      {:error, reason} -> {:error, reason}
    end
  end
end
