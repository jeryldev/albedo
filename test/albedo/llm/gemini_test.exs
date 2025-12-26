defmodule Albedo.LLM.GeminiTest do
  use ExUnit.Case, async: true

  alias Albedo.LLM.Gemini

  describe "chat/2" do
    test "returns error when api_key is missing" do
      assert {:error, :missing_api_key} = Gemini.chat("test prompt")
    end

    test "returns error when api_key is nil" do
      assert {:error, :missing_api_key} = Gemini.chat("test prompt", api_key: nil)
    end

    test "accepts custom model option" do
      result = Gemini.chat("test", api_key: nil, model: "gemini-pro")
      assert {:error, :missing_api_key} = result
    end

    test "accepts temperature option" do
      result = Gemini.chat("test", api_key: nil, temperature: 0.7)
      assert {:error, :missing_api_key} = result
    end

    test "accepts max_tokens option" do
      result = Gemini.chat("test", api_key: nil, max_tokens: 1000)
      assert {:error, :missing_api_key} = result
    end
  end

  describe "response parsing" do
    test "handles standard response structure" do
      response = %{
        "candidates" => [
          %{
            "content" => %{
              "parts" => [
                %{"text" => "Hello, world!"}
              ]
            }
          }
        ]
      }

      assert {:ok, "Hello, world!"} = parse_response(response)
    end

    test "handles multiple parts in response" do
      response = %{
        "candidates" => [
          %{
            "content" => %{
              "parts" => [
                %{"text" => "Part 1"},
                %{"text" => "Part 2"}
              ]
            }
          }
        ]
      }

      assert {:ok, "Part 1Part 2"} = parse_response(response)
    end

    test "handles safety blocked response" do
      response = %{
        "candidates" => [
          %{"finishReason" => "SAFETY"}
        ]
      }

      assert {:error, :safety_blocked} = parse_response(response)
    end

    test "handles API error response" do
      response = %{
        "error" => %{"message" => "Invalid request"}
      }

      assert {:error, {:api_error, %{"message" => "Invalid request"}}} = parse_response(response)
    end

    test "handles unexpected response structure" do
      response = %{"unexpected" => "structure"}
      assert {:error, {:unexpected_response, ^response}} = parse_response(response)
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
end
