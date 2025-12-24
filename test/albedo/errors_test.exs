defmodule Albedo.ErrorsTest do
  use ExUnit.Case, async: true

  alias Albedo.Errors

  describe "CodebaseNotFoundError" do
    test "creates exception with path" do
      error = %Errors.CodebaseNotFoundError{path: "/some/path"}
      assert Exception.message(error) == "Codebase not found at: /some/path"
    end
  end

  describe "LLMError" do
    test "creates exception with provider and reason" do
      error = %Errors.LLMError{provider: "gemini", reason: :rate_limited}
      assert Exception.message(error) == "LLM error (gemini): :rate_limited"
    end
  end

  describe "SessionError" do
    test "creates exception with session_id and reason" do
      error = %Errors.SessionError{session_id: "test-123", reason: :timeout}
      assert Exception.message(error) == "Session test-123 error: :timeout"
    end
  end

  describe "ConfigError" do
    test "creates exception with reason" do
      error = %Errors.ConfigError{reason: :invalid_toml}
      assert Exception.message(error) == "Configuration error: :invalid_toml"
    end
  end

  describe "AgentError" do
    test "creates exception with agent, phase, and reason" do
      error = %Errors.AgentError{
        agent: "DomainResearcher",
        phase: :domain_research,
        reason: :llm_failed
      }

      assert Exception.message(error) ==
               "Agent DomainResearcher failed in phase domain_research: :llm_failed"
    end
  end

  describe "SearchError" do
    test "creates exception with reason" do
      error = %Errors.SearchError{reason: :ripgrep_not_found}
      assert Exception.message(error) == "Search error: :ripgrep_not_found"
    end
  end
end
