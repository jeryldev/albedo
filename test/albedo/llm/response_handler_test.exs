defmodule Albedo.LLM.ResponseHandlerTest do
  use ExUnit.Case, async: true
  use PropCheck

  alias Albedo.LLM.ResponseHandler

  describe "handle_response/3" do
    test "200 with parser returns parsed result" do
      parser = fn body -> {:ok, body["text"]} end
      response = {:ok, %{status: 200, body: %{"text" => "hello"}}}

      assert {:ok, "hello"} = ResponseHandler.handle_response(response, parser, "Test")
    end

    test "429 returns rate_limited" do
      response = {:ok, %{status: 429, body: %{}}}
      assert {:error, :rate_limited} = ResponseHandler.handle_response(response, nil, "Test")
    end

    test "401 returns invalid_api_key" do
      response = {:ok, %{status: 401, body: %{}}}
      assert {:error, :invalid_api_key} = ResponseHandler.handle_response(response, nil, "Test")
    end

    test "403 returns forbidden" do
      response = {:ok, %{status: 403, body: %{}}}
      assert {:error, :forbidden} = ResponseHandler.handle_response(response, nil, "Test")
    end

    test "529 returns overloaded" do
      response = {:ok, %{status: 529, body: %{}}}
      assert {:error, :overloaded} = ResponseHandler.handle_response(response, nil, "Test")
    end

    test "400 returns bad_request with body" do
      body = %{"error" => "invalid request"}
      response = {:ok, %{status: 400, body: body}}

      assert {:error, {:bad_request, ^body}} =
               ResponseHandler.handle_response(response, nil, "Test")
    end

    test "other status codes return http_error" do
      body = %{"error" => "server error"}
      response = {:ok, %{status: 500, body: body}}

      assert {:error, {:http_error, 500, ^body}} =
               ResponseHandler.handle_response(response, nil, "Test")
    end

    test "request error returns request_failed" do
      response = {:error, :timeout}

      assert {:error, {:request_failed, :timeout}} =
               ResponseHandler.handle_response(response, nil, "Test")
    end
  end

  describe "handle_response/3 properties" do
    property "known error codes always return specific atoms" do
      forall status <- oneof([429, 401, 403, 529]) do
        response = {:ok, %{status: status, body: %{}}}
        {:error, reason} = ResponseHandler.handle_response(response, nil, "Test")

        reason in [:rate_limited, :invalid_api_key, :forbidden, :overloaded]
      end
    end

    property "unknown 4xx/5xx codes return http_error tuple" do
      forall status <- such_that(s <- choose(400, 599), when: s not in [400, 401, 403, 429, 529]) do
        body = %{"error" => "test"}
        response = {:ok, %{status: status, body: body}}

        {:error, {:http_error, ^status, ^body}} =
          ResponseHandler.handle_response(response, nil, "Test")

        true
      end
    end

    property "200 always calls parser" do
      forall body <- map_gen() do
        parser = fn b -> {:ok, b} end
        response = {:ok, %{status: 200, body: body}}

        {:ok, ^body} = ResponseHandler.handle_response(response, parser, "Test")
        true
      end
    end

    property "request errors always return request_failed tuple" do
      forall reason <- oneof([:timeout, :closed, :econnrefused, atom()]) do
        response = {:error, reason}

        {:error, {:request_failed, ^reason}} =
          ResponseHandler.handle_response(response, nil, "Test")

        true
      end
    end
  end

  defp map_gen do
    let pairs <- list({atom(), utf8()}) do
      Map.new(pairs)
    end
  end
end
