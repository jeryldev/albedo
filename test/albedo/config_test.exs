defmodule Albedo.ConfigTest do
  use ExUnit.Case, async: true

  alias Albedo.Config

  describe "default configuration" do
    test "load returns config with expected structure" do
      assert {:ok, config} = Config.load()
      # Provider can be any valid value (gemini, claude, openai)
      assert config["llm"]["provider"] in ["gemini", "claude", "openai"]
      assert config["output"]["session_dir"] == "~/.albedo/sessions"
    end
  end

  describe "get/2" do
    test "retrieves nested values with list of keys" do
      config = %{"llm" => %{"provider" => "gemini"}}
      assert Config.get(config, ["llm", "provider"]) == "gemini"
    end

    test "retrieves top-level values with string key" do
      config = %{"llm" => %{"provider" => "gemini"}}
      assert Config.get(config, "llm") == %{"provider" => "gemini"}
    end

    test "returns nil for missing keys" do
      config = %{"llm" => %{}}
      assert Config.get(config, ["llm", "missing"]) == nil
    end
  end

  describe "provider/1" do
    test "returns provider from config" do
      config = %{"llm" => %{"provider" => "openai"}}
      assert Config.provider(config) == "openai"
    end

    test "returns gemini as default" do
      config = %{"llm" => %{}}
      assert Config.provider(config) == "gemini"
    end
  end

  describe "model/1" do
    test "returns correct model for gemini provider" do
      config = %{"llm" => %{"provider" => "gemini"}}
      assert Config.model(config) == "gemini-2.0-flash"
    end

    test "returns correct model for claude provider" do
      config = %{"llm" => %{"provider" => "claude"}}
      assert Config.model(config) == "claude-sonnet-4-20250514"
    end

    test "returns correct model for openai provider" do
      config = %{"llm" => %{"provider" => "openai"}}
      assert Config.model(config) == "gpt-4o"
    end
  end

  describe "env_var_for_provider/1" do
    test "returns correct env var for each provider" do
      assert Config.env_var_for_provider("gemini") == "GEMINI_API_KEY"
      assert Config.env_var_for_provider("claude") == "ANTHROPIC_API_KEY"
      assert Config.env_var_for_provider("openai") == "OPENAI_API_KEY"
    end

    test "returns gemini env var for unknown provider" do
      assert Config.env_var_for_provider("unknown") == "GEMINI_API_KEY"
    end
  end

  describe "temperature/1" do
    test "returns configured temperature" do
      config = %{"llm" => %{"temperature" => 0.5}}
      assert Config.temperature(config) == 0.5
    end

    test "returns default temperature when not configured" do
      config = %{"llm" => %{}}
      assert Config.temperature(config) == 0.3
    end
  end

  describe "exclude_patterns/1" do
    test "returns configured patterns" do
      config = %{"search" => %{"exclude_patterns" => ["node_modules", "dist"]}}
      assert Config.exclude_patterns(config) == ["node_modules", "dist"]
    end

    test "returns empty list when not configured" do
      config = %{"search" => %{}}
      assert Config.exclude_patterns(config) == []
    end
  end

  describe "agent_timeout/1" do
    test "returns configured timeout" do
      config = %{"agents" => %{"timeout" => 600}}
      assert Config.agent_timeout(config) == 600
    end

    test "returns default timeout when not configured" do
      config = %{"agents" => %{}}
      assert Config.agent_timeout(config) == 300
    end
  end

  describe "valid_providers/0" do
    test "returns list of valid providers" do
      providers = Config.valid_providers()
      assert "gemini" in providers
      assert "claude" in providers
      assert "openai" in providers
    end
  end
end
