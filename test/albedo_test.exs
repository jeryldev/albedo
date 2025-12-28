defmodule AlbedoTest do
  use ExUnit.Case, async: false

  @api_key_vars ~w(GEMINI_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY)

  describe "version/0" do
    test "returns version string" do
      version = Albedo.version()
      assert is_binary(version)
      assert version == "0.1.0"
    end
  end

  describe "configured?/0" do
    test "returns false when no API key configured" do
      saved_keys = save_and_clear_api_keys()

      try do
        refute Albedo.configured?()
      after
        restore_api_keys(saved_keys)
      end
    end

    test "returns true when API key is configured" do
      saved_keys = save_and_clear_api_keys()

      try do
        System.put_env("GEMINI_API_KEY", "test-key")
        assert Albedo.configured?()
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
