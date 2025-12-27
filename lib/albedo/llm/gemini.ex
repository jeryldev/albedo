defmodule Albedo.LLM.Gemini do
  @moduledoc """
  Google Gemini API client.
  """

  alias Albedo.LLM.ResponseHandler

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

    if api_key do
      execute_request(prompt, api_key, opts)
    else
      {:error, :missing_api_key}
    end
  end

  defp execute_request(prompt, api_key, opts) do
    model = opts[:model] || @default_model
    url = "#{@base_url}/models/#{model}:generateContent?key=#{api_key}"
    body = build_body(prompt, opts)

    url
    |> Req.post(json: body, receive_timeout: 600_000, retry: false)
    |> ResponseHandler.handle_response(&parse_response/1, "Gemini")
  end

  defp build_body(prompt, opts) do
    %{
      "contents" => [%{"parts" => [%{"text" => prompt}]}],
      "generationConfig" => %{
        "temperature" => opts[:temperature] || 0.3,
        "maxOutputTokens" => opts[:max_tokens] || @default_max_tokens,
        "topP" => 0.95,
        "topK" => 40
      }
    }
  end

  defp parse_response(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    text =
      parts
      |> Enum.filter(&Map.has_key?(&1, "text"))
      |> Enum.map_join("", & &1["text"])

    {:ok, text}
  end

  defp parse_response(%{"candidates" => [%{"finishReason" => "SAFETY"} | _]}),
    do: {:error, :safety_blocked}

  defp parse_response(%{"error" => error}), do: {:error, {:api_error, error}}
  defp parse_response(body), do: {:error, {:unexpected_response, body}}
end
