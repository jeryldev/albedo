defmodule Albedo.Search.PatternMatcher do
  @moduledoc """
  Pattern matching utilities for detecting frameworks, conventions, and code structures.
  """

  @language_indicators %{
    "Elixir" => ["mix.exs", "*.ex", "*.exs"],
    "JavaScript" => ["package.json", "*.js", "*.jsx", "*.mjs"],
    "TypeScript" => ["tsconfig.json", "*.ts", "*.tsx"],
    "Python" => ["requirements.txt", "pyproject.toml", "*.py"],
    "Ruby" => ["Gemfile", "*.rb"],
    "Go" => ["go.mod", "*.go"],
    "Rust" => ["Cargo.toml", "*.rs"]
  }

  @framework_indicators %{
    "Phoenix" => [
      {:file, "lib/*_web/"},
      {:file, "config/config.exs"},
      {:content, "Phoenix.Endpoint"},
      {:content, "Phoenix.Router"},
      {:dep, ":phoenix"}
    ],
    "Phoenix LiveView" => [
      {:file, "*_live.ex"},
      {:file, "*_live/"},
      {:content, "use Phoenix.LiveView"},
      {:dep, ":phoenix_live_view"}
    ],
    "Ecto" => [
      {:file, "priv/repo/migrations/"},
      {:content, "use Ecto.Schema"},
      {:content, "Ecto.Changeset"},
      {:dep, ":ecto"}
    ],
    "Oban" => [
      {:content, "use Oban.Worker"},
      {:dep, ":oban"}
    ],
    "Absinthe" => [
      {:file, "schema.ex"},
      {:file, "resolvers/"},
      {:content, "use Absinthe.Schema"},
      {:dep, ":absinthe"}
    ],
    "Ash" => [
      {:content, "use Ash.Resource"},
      {:content, "use Ash.Domain"},
      {:dep, ":ash"}
    ],
    "React" => [
      {:content, "from 'react'"},
      {:content, "import React"},
      {:file, "src/App.jsx"},
      {:file, "src/App.tsx"}
    ],
    "Next.js" => [
      {:file, "next.config.js"},
      {:file, "next.config.mjs"},
      {:file, "pages/"},
      {:file, "app/"}
    ],
    "Rails" => [
      {:file, "config/routes.rb"},
      {:file, "app/controllers/"},
      {:file, "Gemfile"}
    ],
    "Django" => [
      {:file, "manage.py"},
      {:file, "settings.py"},
      {:file, "wsgi.py"}
    ]
  }

  @database_indicators %{
    "PostgreSQL" => [
      {:content, "Postgrex"},
      {:content, "Postgres"},
      {:content, "postgres"},
      {:content, "postgresql"}
    ],
    "MySQL" => [
      {:content, "MyXQL"},
      {:content, "mysql"}
    ],
    "SQLite" => [
      {:content, "Exqlite"},
      {:content, "sqlite"}
    ],
    "MongoDB" => [
      {:content, "mongodb"},
      {:content, "mongo"}
    ]
  }

  @infrastructure_indicators %{
    "Fly.io" => [{:file, "fly.toml"}],
    "Docker" => [{:file, "Dockerfile"}, {:file, "docker-compose.yml"}],
    "GitHub Actions" => [{:file, ".github/workflows/"}],
    "GitLab CI" => [{:file, ".gitlab-ci.yml"}],
    "Heroku" => [{:file, "Procfile"}, {:file, "elixir_buildpack.config"}],
    "AWS" => [{:file, "serverless.yml"}, {:file, "aws-exports.js"}],
    "Kubernetes" => [{:file, "kubernetes/"}, {:file, "k8s/"}]
  }

  @doc """
  Get all language indicators.
  """
  def language_indicators, do: @language_indicators

  @doc """
  Get all framework indicators.
  """
  def framework_indicators, do: @framework_indicators

  @doc """
  Get all database indicators.
  """
  def database_indicators, do: @database_indicators

  @doc """
  Get all infrastructure indicators.
  """
  def infrastructure_indicators, do: @infrastructure_indicators

  @doc """
  Detect frameworks used in a codebase.
  """
  def detect_frameworks(path, files, file_contents) do
    @framework_indicators
    |> Enum.filter(fn {_framework, indicators} ->
      check_indicators(path, files, file_contents, indicators)
    end)
    |> Enum.map(fn {framework, _} -> framework end)
  end

  @doc """
  Detect database used in a codebase.
  """
  def detect_database(file_contents) do
    @database_indicators
    |> Enum.find(fn {_db, indicators} ->
      Enum.any?(indicators, fn {:content, pattern} ->
        Enum.any?(file_contents, fn content ->
          String.contains?(content, pattern)
        end)
      end)
    end)
    |> case do
      {db, _} -> db
      nil -> nil
    end
  end

  @doc """
  Detect infrastructure/deployment in a codebase.
  """
  def detect_infrastructure(path, files) do
    @infrastructure_indicators
    |> Enum.filter(fn {_infra, indicators} ->
      Enum.any?(indicators, fn {:file, pattern} ->
        file_exists?(path, files, pattern)
      end)
    end)
    |> Enum.map(fn {infra, _} -> infra end)
  end

  @doc """
  Extract Elixir context modules from a path.
  """
  def extract_elixir_contexts(path) do
    lib_path = Path.join(path, "lib")

    case File.ls(lib_path) do
      {:ok, entries} ->
        app_dir =
          entries
          |> Enum.reject(&String.ends_with?(&1, "_web"))
          |> Enum.find(fn entry ->
            full = Path.join(lib_path, entry)
            File.dir?(full) and entry != "mix"
          end)

        if app_dir do
          context_path = Path.join(lib_path, app_dir)

          case File.ls(context_path) do
            {:ok, context_entries} ->
              context_entries
              |> Enum.filter(fn entry ->
                full = Path.join(context_path, entry)
                File.dir?(full) or String.ends_with?(entry, ".ex")
              end)
              |> Enum.map(fn entry ->
                if File.dir?(Path.join(context_path, entry)) do
                  {:context, entry}
                else
                  {:module, String.trim_trailing(entry, ".ex")}
                end
              end)

            _ ->
              []
          end
        else
          []
        end

      _ ->
        []
    end
  end

  @doc """
  Extract dependencies from mix.exs.
  """
  def extract_mix_deps(mix_content) do
    Regex.scan(~r/\{:(\w+),/, mix_content)
    |> Enum.map(fn [_, dep] -> dep end)
  end

  @doc """
  Extract Elixir version from mix.exs or .tool-versions.
  """
  def extract_elixir_version(path) do
    tool_versions = Path.join(path, ".tool-versions")

    cond do
      File.exists?(tool_versions) ->
        case File.read(tool_versions) do
          {:ok, content} ->
            case Regex.run(~r/elixir\s+([\d.]+)/, content) do
              [_, version] -> version
              _ -> nil
            end

          _ ->
            nil
        end

      true ->
        mix_file = Path.join(path, "mix.exs")

        case File.read(mix_file) do
          {:ok, content} ->
            case Regex.run(~r/elixir:\s*"~>\s*([\d.]+)"/, content) do
              [_, version] -> version
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  @doc """
  Generate search patterns for a feature keyword.
  """
  def feature_search_patterns(keyword) do
    %{
      schema: [
        "field :#{keyword}",
        "field :#{keyword}_",
        "field :#{singularize(keyword)}",
        "Ecto.Enum.*#{keyword}",
        "defmodule.*#{String.capitalize(keyword)}"
      ],
      context: [
        "def .*#{keyword}",
        "def list_#{keyword}",
        "def get_#{keyword}",
        "def create_#{keyword}",
        "def update_#{keyword}",
        "def delete_#{keyword}",
        "#{keyword}.*changeset"
      ],
      ui: [
        "#{keyword}.*form",
        "select.*#{keyword}",
        "input.*#{keyword}",
        "phx-change.*#{keyword}",
        "<.input.*#{keyword}"
      ],
      test: [
        "test.*#{keyword}",
        "describe.*#{keyword}",
        "#{keyword}:",
        "assert.*#{keyword}"
      ],
      migration: [
        "add :#{keyword}",
        "modify :#{keyword}",
        "create.*#{keyword}"
      ]
    }
  end

  defp check_indicators(path, files, file_contents, indicators) do
    Enum.any?(indicators, fn
      {:file, pattern} ->
        file_exists?(path, files, pattern)

      {:content, pattern} ->
        Enum.any?(file_contents, fn content ->
          String.contains?(content, pattern)
        end)

      {:dep, dep} ->
        Enum.any?(file_contents, fn content ->
          String.contains?(content, dep)
        end)
    end)
  end

  defp file_exists?(path, files, pattern) do
    if String.contains?(pattern, "*") do
      pattern_path = Path.join(path, pattern)
      not Enum.empty?(Path.wildcard(pattern_path))
    else
      full_path = Path.join(path, pattern)
      File.exists?(full_path) or Enum.any?(files, &String.contains?(&1, pattern))
    end
  end

  defp singularize(word) do
    cond do
      String.ends_with?(word, "ies") ->
        String.replace_suffix(word, "ies", "y")

      String.ends_with?(word, "es") ->
        String.replace_suffix(word, "es", "")

      String.ends_with?(word, "s") ->
        String.replace_suffix(word, "s", "")

      true ->
        word
    end
  end
end
