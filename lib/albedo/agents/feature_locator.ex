defmodule Albedo.Agents.FeatureLocator do
  @moduledoc """
  Phase 2: Feature Location Agent.
  Finds all code related to the specific feature mentioned in the task.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts
  alias Albedo.Search.{PatternMatcher, Ripgrep}

  @impl Albedo.Agents.Base
  def investigate(state) do
    path = state.codebase_path
    task = state.task
    previous_context = state.context

    keywords = extract_keywords(task)
    search_results = search_codebase(path, keywords)

    prompt =
      Prompts.feature_location(task, previous_context, format_search_results(search_results))

    case call_llm(prompt) do
      {:ok, response} ->
        findings = %{
          keywords: keywords,
          search_results: search_results,
          content: response
        }

        {:ok, findings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Albedo.Agents.Base
  def format_output(findings) do
    findings.content
  end

  defp extract_keywords(task) do
    task
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> Enum.reject(&(&1 in stop_words()))
    |> Enum.uniq()
    |> Enum.take(10)
  end

  defp stop_words do
    ~w(the a an is are was were be been being have has had do does did
       will would could should may might must shall can need to from for
       in on at by with about into through during before after above below
       between under over again further then once here there when where why
       how all each few more most other some such no nor not only own same
       so than too very just also now add update create delete remove change
       convert implement make build fix modify)
  end

  defp search_codebase(path, keywords) do
    keyword_results =
      keywords
      |> Enum.flat_map(fn keyword ->
        patterns = PatternMatcher.feature_search_patterns(keyword)

        Enum.flat_map(patterns, fn {category, search_patterns} ->
          search_patterns
          |> Enum.flat_map(fn pattern ->
            case Ripgrep.search(pattern, path: path, context: 2, max_count: 10) do
              {:ok, results} -> Enum.map(results, &Map.put(&1, :category, category))
              _ -> []
            end
          end)
        end)
      end)

    schema_results = search_schemas(path, keywords)
    migration_results = search_migrations(path, keywords)
    test_results = search_tests(path, keywords)

    %{
      keyword_matches: keyword_results,
      schemas: schema_results,
      migrations: migration_results,
      tests: test_results
    }
  end

  defp search_schemas(path, keywords) do
    patterns =
      keywords
      |> Enum.flat_map(fn kw ->
        ["field :#{kw}", "field :#{kw}_", "belongs_to :#{kw}", "has_many :#{kw}"]
      end)

    case Ripgrep.search_multiple(patterns, path: path, type: "elixir") do
      {:ok, results} -> results
      _ -> []
    end
  end

  defp search_migrations(path, keywords) do
    migrations_path = Path.join([path, "priv", "repo", "migrations"])

    if File.dir?(migrations_path) do
      patterns = keywords |> Enum.flat_map(fn kw -> [":#{kw}", "\"#{kw}\""] end)

      case Ripgrep.search_multiple(patterns, path: migrations_path) do
        {:ok, results} -> results
        _ -> []
      end
    else
      []
    end
  end

  defp search_tests(path, keywords) do
    test_path = Path.join(path, "test")

    if File.dir?(test_path) do
      patterns = keywords |> Enum.flat_map(fn kw -> ["test.*#{kw}", "describe.*#{kw}"] end)

      case Ripgrep.search_multiple(patterns, path: test_path) do
        {:ok, results} -> results
        _ -> []
      end
    else
      []
    end
  end

  defp format_search_results(results) do
    sections = []

    sections =
      if results.keyword_matches != [] do
        keyword_section =
          results.keyword_matches
          |> Enum.group_by(& &1.category)
          |> Enum.map_join("\n", fn {category, matches} ->
            match_text =
              matches
              |> Enum.take(10)
              |> Enum.map_join("\n", &format_match/1)

            """
            ### #{category |> to_string() |> String.capitalize()}
            #{match_text}
            """
          end)

        sections ++ ["## Keyword Matches\n#{keyword_section}"]
      else
        sections
      end

    sections =
      if results.schemas != [] do
        schema_section =
          results.schemas
          |> Enum.take(10)
          |> Enum.map_join("\n", &format_match/1)

        sections ++ ["## Schema Matches\n#{schema_section}"]
      else
        sections
      end

    sections =
      if results.migrations != [] do
        migration_section =
          results.migrations
          |> Enum.take(5)
          |> Enum.map_join("\n", &format_match/1)

        sections ++ ["## Migration Matches\n#{migration_section}"]
      else
        sections
      end

    sections =
      if results.tests != [] do
        test_section =
          results.tests
          |> Enum.take(5)
          |> Enum.map_join("\n", &format_match/1)

        sections ++ ["## Test Matches\n#{test_section}"]
      else
        sections
      end

    if Enum.empty?(sections) do
      "No matches found for the given keywords."
    else
      Enum.join(sections, "\n\n")
    end
  end

  defp format_match(result) do
    file = result.file

    matches =
      Enum.map_join(result.matches, "\n", fn m ->
        "  Line #{m.line}: #{String.trim(m.content)}"
      end)

    """
    **File:** #{file}
    #{matches}
    """
  end
end
