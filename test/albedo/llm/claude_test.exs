defmodule Albedo.LLM.ClaudeTest do
  use ExUnit.Case, async: true

  alias Albedo.LLM.Claude

  describe "chat/2" do
    test "returns error when api_key is missing" do
      assert {:error, :missing_api_key} = Claude.chat("test prompt")
    end

    test "returns error when api_key is nil" do
      assert {:error, :missing_api_key} = Claude.chat("test prompt", api_key: nil)
    end

    test "accepts custom model option" do
      result = Claude.chat("test", api_key: nil, model: "claude-3-opus")
      assert {:error, :missing_api_key} = result
    end

    test "accepts temperature option" do
      result = Claude.chat("test", api_key: nil, temperature: 0.7)
      assert {:error, :missing_api_key} = result
    end

    test "accepts max_tokens option" do
      result = Claude.chat("test", api_key: nil, max_tokens: 1000)
      assert {:error, :missing_api_key} = result
    end
  end

  describe "response parsing" do
    test "handles standard response structure" do
      response = %{
        "content" => [
          %{"type" => "text", "text" => "Hello, world!"}
        ]
      }

      assert {:ok, "Hello, world!"} = parse_response(response)
    end

    test "handles multiple content blocks" do
      response = %{
        "content" => [
          %{"type" => "text", "text" => "Part 1"},
          %{"type" => "text", "text" => "Part 2"}
        ]
      }

      assert {:ok, "Part 1Part 2"} = parse_response(response)
    end

    test "handles empty content array" do
      response = %{"content" => []}
      assert {:ok, ""} = parse_response(response)
    end

    test "handles error response" do
      response = %{
        "error" => %{"type" => "invalid_request", "message" => "Bad request"}
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
