defmodule Albedo.LLM.OpenAI do
  @moduledoc """
  OpenAI API client.
  """

  @behaviour Albedo.LLM.Provider

  alias Albedo.LLM.ResponseHandler

  @base_url "https://api.openai.com/v1"
  @default_model "gpt-4o"
  @default_max_tokens 8192

  @doc """
  Send a chat request to OpenAI.

  Options:
    - :api_key - API key (required)
    - :model - Model to use (default: gpt-4o)
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
    url = "#{@base_url}/chat/completions"
    headers = [{"Authorization", "Bearer #{api_key}"}, {"content-type", "application/json"}]
    body = build_body(prompt, opts)

    url
    |> Req.post(json: body, headers: headers, receive_timeout: 600_000, retry: false)
    |> ResponseHandler.handle_response(&parse_response/1, "OpenAI")
  end

  defp build_body(prompt, opts) do
    %{
      "model" => opts[:model] || @default_model,
      "max_tokens" => opts[:max_tokens] || @default_max_tokens,
      "temperature" => opts[:temperature] || 0.3,
      "messages" => [%{"role" => "user", "content" => prompt}]
    }
  end

  defp parse_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}),
    do: {:ok, content}

  defp parse_response(%{"error" => error}), do: {:error, {:api_error, error}}
  defp parse_response(body), do: {:error, {:unexpected_response, body}}
end
