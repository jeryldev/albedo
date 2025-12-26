defmodule Albedo.LLM.OpenAI do
  @moduledoc """
  OpenAI API client.
  """

  require Logger

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
    |> handle_response()
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

  defp handle_response({:ok, %{status: 400, body: body}}) do
    Logger.error("OpenAI bad request: #{inspect(body)}")
    {:error, {:bad_request, body}}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    Logger.error("OpenAI error (#{status}): #{inspect(body)}")
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, reason}) do
    Logger.error("OpenAI request failed: #{inspect(reason)}")
    {:error, {:request_failed, reason}}
  end

  defp parse_response(body) do
    case body do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} ->
        {:ok, content}

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
