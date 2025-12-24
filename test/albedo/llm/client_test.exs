defmodule Albedo.LLM.ClientTest do
  use ExUnit.Case, async: true

  alias Albedo.LLM.Client

  describe "provider_available?/1" do
    test "returns false for provider without API key" do
      System.delete_env("FAKE_API_KEY_TEST")
      refute Client.provider_available?("fake_provider")
    end
  end

  describe "available_providers/0" do
    test "returns list of providers" do
      providers = Client.available_providers()
      assert is_list(providers)
    end
  end

  describe "chat/2" do
    test "returns error for unknown provider" do
      result = Client.chat("test", provider: "unknown_provider")
      assert {:error, {:unknown_provider, "unknown_provider"}} = result
    end
  end

  describe "chat!/2" do
    test "raises for unknown provider" do
      assert_raise Albedo.Errors.LLMError, fn ->
        Client.chat!("test", provider: "unknown_provider")
      end
    end
  end
end
