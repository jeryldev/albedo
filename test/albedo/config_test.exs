defmodule Albedo.ConfigTest do
  use ExUnit.Case, async: true

  alias Albedo.Config

  describe "default configuration" do
    test "load returns default config when no file exists" do
      assert {:ok, config} = Config.load()
      assert config["llm"]["provider"] == "gemini"
      assert config["llm"]["model"] == "gemini-2.0-flash"
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

  describe "model/2" do
    test "returns primary model for primary provider" do
      config = %{
        "llm" => %{
          "provider" => "gemini",
          "model" => "gemini-2.0-flash"
        }
      }

      assert Config.model(config, "gemini") == "gemini-2.0-flash"
    end

    test "returns fallback model for fallback provider" do
      config = %{
        "llm" => %{
          "provider" => "gemini",
          "model" => "gemini-2.0-flash",
          "fallback" => %{
            "provider" => "claude",
            "model" => "claude-sonnet-4-20250514"
          }
        }
      }

      assert Config.model(config, "claude") == "claude-sonnet-4-20250514"
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
end
