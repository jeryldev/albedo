defmodule Albedo.Search.PatternMatcherTest do
  use ExUnit.Case, async: true

  alias Albedo.Search.PatternMatcher

  describe "language_indicators/0" do
    test "returns language indicators map" do
      indicators = PatternMatcher.language_indicators()

      assert is_map(indicators)
      assert Map.has_key?(indicators, "Elixir")
      assert Map.has_key?(indicators, "JavaScript")
      assert Map.has_key?(indicators, "Python")
    end

    test "includes file patterns for each language" do
      indicators = PatternMatcher.language_indicators()

      assert "mix.exs" in indicators["Elixir"]
      assert "package.json" in indicators["JavaScript"]
      assert "requirements.txt" in indicators["Python"]
    end
  end

  describe "framework_indicators/0" do
    test "returns framework indicators map" do
      indicators = PatternMatcher.framework_indicators()

      assert is_map(indicators)
      assert Map.has_key?(indicators, "Phoenix")
      assert Map.has_key?(indicators, "Phoenix LiveView")
      assert Map.has_key?(indicators, "Ecto")
    end

    test "includes file and content patterns" do
      indicators = PatternMatcher.framework_indicators()
      phoenix_indicators = indicators["Phoenix"]

      assert {:file, "lib/*_web/"} in phoenix_indicators
      assert {:dep, ":phoenix"} in phoenix_indicators
    end
  end

  describe "database_indicators/0" do
    test "returns database indicators map" do
      indicators = PatternMatcher.database_indicators()

      assert is_map(indicators)
      assert Map.has_key?(indicators, "PostgreSQL")
      assert Map.has_key?(indicators, "MySQL")
      assert Map.has_key?(indicators, "SQLite")
    end
  end

  describe "extract_mix_deps/1" do
    test "extracts dependencies from mix.exs content" do
      content = """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:phoenix, "~> 1.7"},
            {:ecto, "~> 3.11"},
            {:jason, "~> 1.4"}
          ]
        end
      end
      """

      deps = PatternMatcher.extract_mix_deps(content)

      assert "phoenix" in deps
      assert "ecto" in deps
      assert "jason" in deps
    end

    test "returns empty list when no deps found" do
      content = "defmodule Empty do end"
      deps = PatternMatcher.extract_mix_deps(content)

      assert deps == []
    end
  end

  describe "feature_search_patterns/1" do
    test "generates search patterns for a keyword" do
      patterns = PatternMatcher.feature_search_patterns("status")

      assert is_map(patterns)
      assert Map.has_key?(patterns, :schema)
      assert Map.has_key?(patterns, :context)
      assert Map.has_key?(patterns, :ui)
      assert Map.has_key?(patterns, :test)
      assert Map.has_key?(patterns, :migration)
    end

    test "includes keyword in schema patterns" do
      patterns = PatternMatcher.feature_search_patterns("order")

      assert "field :order" in patterns.schema
      assert "def .*order" in patterns.context
    end

    test "includes keyword in test patterns" do
      patterns = PatternMatcher.feature_search_patterns("cart")

      assert "test.*cart" in patterns.test
      assert "describe.*cart" in patterns.test
    end
  end

  describe "detect_database/1" do
    test "detects PostgreSQL from content" do
      contents = ["adapter: Ecto.Adapters.Postgres", "hostname: localhost"]
      result = PatternMatcher.detect_database(contents)

      assert result == "PostgreSQL"
    end

    test "detects MySQL from content" do
      contents = ["adapter: MyXQL", "pool_size: 10"]
      result = PatternMatcher.detect_database(contents)

      assert result == "MySQL"
    end

    test "returns nil when no database detected" do
      contents = ["some random content"]
      result = PatternMatcher.detect_database(contents)

      assert result == nil
    end
  end
end
