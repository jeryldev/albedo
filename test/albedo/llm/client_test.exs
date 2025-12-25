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

  describe "chat!/2" do
    test "raises when API key is missing" do
      # This will fail because the test doesn't have real API keys set
      assert_raise Albedo.Errors.LLMError, fn ->
        Client.chat!("test")
      end
    end
  end
end
