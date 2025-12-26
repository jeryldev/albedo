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

    if api_key do
      execute_request(prompt, api_key, opts)
    else
      {:error, :missing_api_key}
    end
  end

  defp execute_request(prompt, api_key, opts) do
    url = "#{@base_url}/messages"
    headers = build_headers(api_key)
    body = build_body(prompt, opts)

    url
    |> Req.post(json: body, headers: headers, receive_timeout: 600_000, retry: false)
    |> handle_response()
  end

  defp build_headers(api_key) do
    [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]
  end

  defp build_body(prompt, opts) do
    %{
      "model" => opts[:model] || @default_model,
      "max_tokens" => opts[:max_tokens] || @default_max_tokens,
      "temperature" => opts[:temperature] || 0.3,
      "messages" => [%{"role" => "user", "content" => prompt}]
    }
  end

  defp handle_response({:ok, %{status: 200, body: response_body}}),
    do: parse_response(response_body)

  defp handle_response({:ok, %{status: 429}}), do: {:error, :rate_limited}
  defp handle_response({:ok, %{status: 401}}), do: {:error, :invalid_api_key}
  defp handle_response({:ok, %{status: 403}}), do: {:error, :forbidden}
  defp handle_response({:ok, %{status: 529}}), do: {:error, :overloaded}

  defp handle_response({:ok, %{status: 400, body: body}}) do
    Logger.error("Claude bad request: #{inspect(body)}")
    {:error, {:bad_request, body}}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    Logger.error("Claude error (#{status}): #{inspect(body)}")
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, reason}) do
    Logger.error("Claude request failed: #{inspect(reason)}")
    {:error, {:request_failed, reason}}
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
end
