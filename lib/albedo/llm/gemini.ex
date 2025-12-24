defmodule Albedo.LLM.Gemini do
  @moduledoc """
  Google Gemini API client.
  """

  require Logger

  @base_url "https://generativelanguage.googleapis.com/v1beta"
  @default_model "gemini-2.0-flash-exp"
  @default_max_tokens 8192

  @doc """
  Send a chat request to Gemini.

  Options:
    - :api_key - API key (required)
    - :model - Model to use (default: gemini-2.0-flash)
    - :temperature - Temperature (default: 0.3)
    - :max_tokens - Maximum tokens (default: 8192)
  """
  def chat(prompt, opts \\ []) do
    api_key = opts[:api_key]
    model = opts[:model] || @default_model
    temperature = opts[:temperature] || 0.3
    max_tokens = opts[:max_tokens] || @default_max_tokens

    if api_key do
      url = "#{@base_url}/models/#{model}:generateContent?key=#{api_key}"

      body = %{
        "contents" => [
          %{
            "parts" => [
              %{"text" => prompt}
            ]
          }
        ],
        "generationConfig" => %{
          "temperature" => temperature,
          "maxOutputTokens" => max_tokens,
          "topP" => 0.95,
          "topK" => 40
        }
      }

      case Req.post(url, json: body) do
        {:ok, %{status: 200, body: response_body}} ->
          parse_response(response_body)

        {:ok, %{status: 429}} ->
          {:error, :rate_limited}

        {:ok, %{status: 400, body: body}} ->
          Logger.error("Gemini bad request: #{inspect(body)}")
          {:error, {:bad_request, body}}

        {:ok, %{status: 401}} ->
          {:error, :invalid_api_key}

        {:ok, %{status: 403}} ->
          {:error, :forbidden}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Gemini error (#{status}): #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.error("Gemini request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    else
      {:error, :missing_api_key}
    end
  end

  defp parse_response(body) do
    case body do
      %{"candidates" => [%{"content" => %{"parts" => parts}} | _]} ->
        text =
          parts
          |> Enum.filter(&Map.has_key?(&1, "text"))
          |> Enum.map_join("", & &1["text"])

        {:ok, text}

      %{"candidates" => [%{"finishReason" => "SAFETY"} | _]} ->
        {:error, :safety_blocked}

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
