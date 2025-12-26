defmodule Albedo.ErrorsTest do
  use ExUnit.Case, async: true

  alias Albedo.Errors

  describe "LLMError" do
    test "creates exception with provider and reason" do
      error = %Errors.LLMError{provider: "gemini", reason: :rate_limited}
      assert Exception.message(error) == "LLM error (gemini): :rate_limited"
    end
  end

  describe "ConfigError" do
    test "creates exception with reason" do
      error = %Errors.ConfigError{reason: :invalid_toml}
      assert Exception.message(error) == "Configuration error: :invalid_toml"
    end
  end
end
