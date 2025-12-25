defmodule Albedo.Agents.FeatureLocatorTest do
  use ExUnit.Case, async: true

  @stop_words ~w(the a an is are was were be been being have has had do does did
    will would could should may might must shall can need to from for
    in on at by with about into through during before after above below
    between under over again further then once here there when where why
    how all each few more most other some such no nor not only own same
    so than too very just also now add update create delete remove change
    convert implement make build fix modify)

  @max_keywords 10

  describe "keyword extraction" do
    test "extracts meaningful keywords from task" do
      task = "Add user authentication with email and password"
      keywords = extract_keywords(task)

      assert "user" in keywords
      assert "authentication" in keywords
      assert "email" in keywords
      assert "password" in keywords
    end

    test "removes stop words" do
      task = "Add the user to the system with a password"
      keywords = extract_keywords(task)

      refute "the" in keywords
      refute "to" in keywords
      refute "with" in keywords
      refute "a" in keywords
      refute "add" in keywords
    end

    test "removes punctuation" do
      task = "Fix bug: user's email isn't validated correctly!"
      keywords = extract_keywords(task)

      assert "bug" in keywords
      assert "user" in keywords
      assert "email" in keywords
      assert "validated" in keywords
      assert "correctly" in keywords
    end

    test "limits keywords count" do
      task =
        "keyword1 keyword2 keyword3 keyword4 keyword5 keyword6 keyword7 keyword8 keyword9 keyword10 keyword11 keyword12"

      keywords = extract_keywords(task)

      assert length(keywords) <= @max_keywords
    end

    test "returns unique keywords" do
      task = "user user account account profile"
      keywords = extract_keywords(task)

      assert length(keywords) == length(Enum.uniq(keywords))
    end

    test "handles empty task" do
      assert extract_keywords("") == []
    end

    test "handles task with only stop words" do
      task = "add the to a with from"
      keywords = extract_keywords(task)

      assert keywords == []
    end
  end

  describe "search result formatting" do
    test "formats empty results" do
      results = %{
        keyword_matches: [],
        schemas: [],
        migrations: [],
        tests: [],
        file_contents: %{}
      }

      formatted = format_search_results(results)

      assert is_binary(formatted)
    end

    test "formats results with matches" do
      results = %{
        keyword_matches: [%{file: "lib/user.ex", line: 10, content: "def get_user"}],
        schemas: [%{file: "lib/accounts/user.ex"}],
        migrations: [],
        tests: [%{file: "test/accounts_test.exs"}],
        file_contents: %{"lib/user.ex" => "defmodule User\nend"}
      }

      formatted = format_search_results(results)

      assert formatted =~ "user.ex"
    end
  end

  describe "unique file collection" do
    test "collects unique files from multiple result sets" do
      results1 = [%{file: "/path/a.ex"}, %{file: "/path/b.ex"}]
      results2 = [%{file: "/path/b.ex"}, %{file: "/path/c.ex"}]

      unique = collect_unique_files([results1, results2])

      assert length(unique) == 3
      assert "/path/a.ex" in unique
      assert "/path/b.ex" in unique
      assert "/path/c.ex" in unique
    end

    test "handles empty results" do
      unique = collect_unique_files([[], []])

      assert unique == []
    end
  end

  defp extract_keywords(task) do
    task
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> Enum.reject(&(&1 in @stop_words))
    |> Enum.uniq()
    |> Enum.take(@max_keywords)
  end

  defp format_search_results(results) do
    sections = []

    sections =
      if results.keyword_matches != [] do
        files = Enum.map(results.keyword_matches, & &1.file) |> Enum.uniq()
        sections ++ ["Keyword matches in: #{Enum.join(files, ", ")}"]
      else
        sections
      end

    sections =
      if results.schemas != [] do
        files = Enum.map(results.schemas, & &1.file) |> Enum.uniq()
        sections ++ ["Schemas: #{Enum.join(files, ", ")}"]
      else
        sections
      end

    sections =
      if results.tests != [] do
        files = Enum.map(results.tests, & &1.file) |> Enum.uniq()
        sections ++ ["Tests: #{Enum.join(files, ", ")}"]
      else
        sections
      end

    Enum.join(sections, "\n")
  end

  defp collect_unique_files(result_lists) do
    result_lists
    |> List.flatten()
    |> Enum.map(& &1.file)
    |> Enum.uniq()
  end
end
