defmodule Albedo.Agents.FeatureLocator do
  @moduledoc """
  Phase 2: Feature Location Agent.
  Finds all code related to the specific feature mentioned in the task.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts
  alias Albedo.Search.{PatternMatcher, Ripgrep}

  @max_keywords 10
  @max_search_results 10
  @max_key_files 10
  @max_file_size 5000
  @max_schema_results 10
  @max_migration_results 5
  @max_test_results 5

  @stop_words ~w(the a an is are was were be been being have has had do does did
    will would could should may might must shall can need to from for
    in on at by with about into through during before after above below
    between under over again further then once here there when where why
    how all each few more most other some such no nor not only own same
    so than too very just also now add update create delete remove change
    convert implement make build fix modify)

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
  def format_output(findings), do: findings.content

  defp extract_keywords(task) do
    task
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> Enum.reject(&(&1 in @stop_words))
    |> Enum.uniq()
    |> Enum.take(@max_keywords)
  end

  defp search_codebase(path, keywords) do
    keyword_results = search_by_keywords(path, keywords)
    schema_results = search_schemas(path, keywords)
    migration_results = search_migrations(path, keywords)
    test_results = search_tests(path, keywords)

    all_files =
      collect_unique_files([keyword_results, schema_results, migration_results, test_results])

    file_contents = read_key_files(all_files)

    %{
      keyword_matches: keyword_results,
      schemas: schema_results,
      migrations: migration_results,
      tests: test_results,
      file_contents: file_contents
    }
  end

  defp search_by_keywords(path, keywords) do
    Enum.flat_map(keywords, fn keyword ->
      keyword
      |> PatternMatcher.feature_search_patterns()
      |> Enum.flat_map(&search_pattern_category(path, &1))
    end)
  end

  defp search_pattern_category(path, {category, search_patterns}) do
    Enum.flat_map(search_patterns, fn pattern ->
      case Ripgrep.search(pattern, path: path, context: 2, max_count: @max_search_results) do
        {:ok, results} -> Enum.map(results, &Map.put(&1, :category, category))
        _ -> []
      end
    end)
  end

  defp collect_unique_files(result_lists) do
    result_lists
    |> Enum.flat_map(&Enum.map(&1, fn r -> r.file end))
    |> Enum.uniq()
  end

  defp read_key_files(files) do
    files
    |> Enum.take(@max_key_files)
    |> Enum.flat_map(&read_file_content/1)
    |> Map.new()
  end

  defp read_file_content(file) do
    case File.read(file) do
      {:ok, content} -> [{file, truncate_content(content)}]
      _ -> []
    end
  end

  defp truncate_content(content) when byte_size(content) > @max_file_size do
    String.slice(content, 0, @max_file_size) <> "\n\n... [truncated]"
  end

  defp truncate_content(content), do: content

  defp search_schemas(path, keywords) do
    patterns =
      Enum.flat_map(keywords, fn kw ->
        ["field :#{kw}", "field :#{kw}_", "belongs_to :#{kw}", "has_many :#{kw}"]
      end)

    search_with_patterns(path, patterns, type: "elixir")
  end

  defp search_migrations(path, keywords) do
    migrations_path = Path.join([path, "priv", "repo", "migrations"])

    if File.dir?(migrations_path) do
      patterns = Enum.flat_map(keywords, fn kw -> [":#{kw}", "\"#{kw}\""] end)
      search_with_patterns(migrations_path, patterns)
    else
      []
    end
  end

  defp search_tests(path, keywords) do
    test_path = Path.join(path, "test")

    if File.dir?(test_path) do
      patterns = Enum.flat_map(keywords, fn kw -> ["test.*#{kw}", "describe.*#{kw}"] end)
      search_with_patterns(test_path, patterns)
    else
      []
    end
  end

  defp search_with_patterns(path, patterns, opts \\ []) do
    search_opts = Keyword.merge([path: path], opts)

    case Ripgrep.search_multiple(patterns, search_opts) do
      {:ok, results} -> results
      _ -> []
    end
  end

  defp format_search_results(results) do
    sections =
      [
        format_keyword_matches(results.keyword_matches),
        format_schema_matches(results.schemas),
        format_migration_matches(results.migrations),
        format_test_matches(results.tests),
        format_file_contents(results[:file_contents])
      ]
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(sections) do
      "No matches found for the given keywords."
    else
      Enum.join(sections, "\n\n")
    end
  end

  defp format_keyword_matches([]), do: nil

  defp format_keyword_matches(matches) do
    content =
      matches
      |> Enum.group_by(& &1.category)
      |> Enum.map_join("\n", fn {category, category_matches} ->
        match_text =
          category_matches
          |> Enum.take(@max_search_results)
          |> Enum.map_join("\n", &format_match/1)

        """
        ### #{category |> to_string() |> String.capitalize()}
        #{match_text}
        """
      end)

    "## Keyword Matches\n#{content}"
  end

  defp format_schema_matches([]), do: nil

  defp format_schema_matches(schemas) do
    content =
      schemas
      |> Enum.take(@max_schema_results)
      |> Enum.map_join("\n", &format_match/1)

    "## Schema Matches\n#{content}"
  end

  defp format_migration_matches([]), do: nil

  defp format_migration_matches(migrations) do
    content =
      migrations
      |> Enum.take(@max_migration_results)
      |> Enum.map_join("\n", &format_match/1)

    "## Migration Matches\n#{content}"
  end

  defp format_test_matches([]), do: nil

  defp format_test_matches(tests) do
    content =
      tests
      |> Enum.take(@max_test_results)
      |> Enum.map_join("\n", &format_match/1)

    "## Test Matches\n#{content}"
  end

  defp format_file_contents(nil), do: nil
  defp format_file_contents(contents) when map_size(contents) == 0, do: nil

  defp format_file_contents(contents) do
    content =
      Enum.map_join(contents, "\n\n", fn {file, file_content} ->
        lang = file |> Path.extname() |> String.trim_leading(".")

        """
        ### #{file}
        ```#{lang}
        #{file_content}
        ```
        """
      end)

    "## Source Files\n#{content}"
  end

  defp format_match(result) do
    matches =
      Enum.map_join(result.matches, "\n", fn m ->
        "  Line #{m.line}: #{String.trim(m.content)}"
      end)

    """
    **File:** #{result.file}
    #{matches}
    """
  end
end
