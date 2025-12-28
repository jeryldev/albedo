defmodule Albedo.LLM.Claude do
  @moduledoc """
  Anthropic Claude API client.
  """

  @behaviour Albedo.LLM.Provider

  alias Albedo.LLM.ResponseHandler

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
  @impl Albedo.LLM.Provider
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
    |> ResponseHandler.handle_response(&parse_response/1, "Claude")
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

  defp parse_response(%{"content" => content}) when is_list(content) do
    text =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("", & &1["text"])

    {:ok, text}
  end

  defp parse_response(%{"error" => error}), do: {:error, {:api_error, error}}
  defp parse_response(body), do: {:error, {:unexpected_response, body}}
end
