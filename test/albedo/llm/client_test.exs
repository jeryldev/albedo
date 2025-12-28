defmodule Albedo.LLM.ClientTest do
  use ExUnit.Case, async: false

  alias Albedo.LLM.Client

  @api_key_vars ~w(GEMINI_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY)

  describe "provider_available?/1" do
    test "returns false for provider without API key" do
      saved_keys = save_and_clear_api_keys()

      try do
        refute Client.provider_available?("gemini")
        refute Client.provider_available?("claude")
        refute Client.provider_available?("openai")
      after
        restore_api_keys(saved_keys)
      end
    end

    test "returns true when provider has API key" do
      saved_keys = save_and_clear_api_keys()

      try do
        System.put_env("GEMINI_API_KEY", "test-key")
        assert Client.provider_available?("gemini")
        refute Client.provider_available?("claude")
      after
        restore_api_keys(saved_keys)
      end
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
      saved_keys = save_and_clear_api_keys()

      try do
        assert_raise Albedo.Errors.LLMError, fn ->
          Client.chat!("test")
        end
      after
        restore_api_keys(saved_keys)
      end
    end
  end

  defp save_and_clear_api_keys do
    saved =
      Enum.map(@api_key_vars, fn var ->
        {var, System.get_env(var)}
      end)

    Enum.each(@api_key_vars, &System.delete_env/1)
    saved
  end

  defp restore_api_keys(saved_keys) do
    Enum.each(saved_keys, fn
      {var, nil} -> System.delete_env(var)
      {var, value} -> System.put_env(var, value)
    end)
  end
end
