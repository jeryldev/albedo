defmodule Albedo.LLM.OpenAITest do
  use ExUnit.Case, async: true

  alias Albedo.LLM.OpenAI

  describe "chat/2" do
    test "returns error when api_key is missing" do
      assert {:error, :missing_api_key} = OpenAI.chat("test prompt")
    end

    test "returns error when api_key is nil" do
      assert {:error, :missing_api_key} = OpenAI.chat("test prompt", api_key: nil)
    end

    test "accepts custom model option" do
      result = OpenAI.chat("test", api_key: nil, model: "gpt-4")
      assert {:error, :missing_api_key} = result
    end

    test "accepts temperature option" do
      result = OpenAI.chat("test", api_key: nil, temperature: 0.7)
      assert {:error, :missing_api_key} = result
    end

    test "accepts max_tokens option" do
      result = OpenAI.chat("test", api_key: nil, max_tokens: 1000)
      assert {:error, :missing_api_key} = result
    end
  end

  describe "response parsing" do
    test "handles standard response structure" do
      response = %{
        "choices" => [
          %{
            "message" => %{
              "content" => "Hello, world!"
            }
          }
        ]
      }

      assert {:ok, "Hello, world!"} = parse_response(response)
    end

    test "handles empty choices" do
      response = %{"choices" => []}
      assert {:error, {:unexpected_response, _}} = parse_response(response)
    end

    test "handles error response" do
      response = %{
        "error" => %{
          "message" => "Invalid API key",
          "type" => "invalid_request_error"
        }
      }

      assert {:error, {:api_error, _}} = parse_response(response)
    end

    test "handles unexpected response structure" do
      response = %{"unexpected" => "structure"}
      assert {:error, {:unexpected_response, ^response}} = parse_response(response)
    end
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
end
