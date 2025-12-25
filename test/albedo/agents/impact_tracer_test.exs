defmodule Albedo.Agents.ImpactTracerTest do
  use ExUnit.Case, async: true

  @max_feature_files 20

  describe "feature file extraction" do
    test "extracts files from keyword matches and schemas" do
      context = %{
        feature_location: %{
          search_results: %{
            keyword_matches: [
              %{file: "lib/accounts/user.ex"},
              %{file: "lib/accounts/accounts.ex"}
            ],
            schemas: [
              %{file: "lib/accounts/user.ex"},
              %{file: "lib/accounts/profile.ex"}
            ]
          }
        }
      }

      files = extract_feature_files(context)

      assert length(files) == 3
      assert "lib/accounts/user.ex" in files
      assert "lib/accounts/accounts.ex" in files
      assert "lib/accounts/profile.ex" in files
    end

    test "returns empty list for missing context" do
      assert extract_feature_files(%{}) == []
      assert extract_feature_files(%{feature_location: nil}) == []
    end

    test "limits number of files" do
      matches = Enum.map(1..30, &%{file: "lib/file_#{&1}.ex"})

      context = %{
        feature_location: %{
          search_results: %{
            keyword_matches: matches,
            schemas: []
          }
        }
      }

      files = extract_feature_files(context)

      assert length(files) <= @max_feature_files
    end
  end

  describe "file extraction helper" do
    test "extracts file paths from results" do
      results = [
        %{file: "lib/a.ex", line: 10},
        %{file: "lib/b.ex", line: 20}
      ]

      files = extract_files_from(results)

      assert files == ["lib/a.ex", "lib/b.ex"]
    end

    test "handles nil input" do
      assert extract_files_from(nil) == []
    end

    test "handles empty list" do
      assert extract_files_from([]) == []
    end
  end

  describe "module name extraction" do
    test "extracts module from file path" do
      assert extract_module_name("lib/my_app/accounts/user.ex") =~ "User"
      assert extract_module_name("lib/my_app_web/live/page_live.ex") =~ "PageLive"
    end

    test "handles simple file names" do
      result = extract_module_name("user.ex")
      assert result =~ "User"
    end
  end

  describe "dependency building" do
    test "builds direct dependency struct" do
      source = "lib/user.ex"
      result = %{file: "lib/accounts.ex", line: 5, content: "alias MyApp.User"}

      dep = build_direct_dependency(source, result)

      assert dep.source_file == source
      assert dep.dependent_file == "lib/accounts.ex"
      assert dep.dependency_type == :alias
    end

    test "detects import dependency type" do
      source = "lib/user.ex"
      result = %{file: "lib/accounts.ex", line: 5, content: "import MyApp.User"}

      dep = build_direct_dependency(source, result)

      assert dep.dependency_type == :import
    end

    test "detects use dependency type" do
      source = "lib/user.ex"
      result = %{file: "lib/accounts.ex", line: 5, content: "use MyApp.User"}

      dep = build_direct_dependency(source, result)

      assert dep.dependency_type == :use
    end
  end

  describe "dependency info formatting" do
    test "formats empty dependency info" do
      info = %{
        direct: [],
        indirect: [],
        queries: [],
        side_effects: []
      }

      formatted = format_dependency_info(info)

      assert is_binary(formatted)
    end

    test "formats dependency info with data" do
      info = %{
        direct: [%{source_file: "a.ex", dependent_file: "b.ex", dependency_type: :alias}],
        indirect: [],
        queries: [],
        side_effects: []
      }

      formatted = format_dependency_info(info)

      assert formatted =~ "a.ex"
    end
  end

  defp extract_feature_files(context) do
    search_results = get_in(context, [:feature_location, :search_results]) || %{}

    keyword_files = extract_files_from(search_results[:keyword_matches])
    schema_files = extract_files_from(search_results[:schemas])

    (keyword_files ++ schema_files)
    |> Enum.uniq()
    |> Enum.take(@max_feature_files)
  end

  defp extract_files_from(nil), do: []
  defp extract_files_from(results), do: Enum.map(results, & &1.file)

  defp extract_module_name(file) do
    file
    |> Path.basename(".ex")
    |> Macro.camelize()
  end

  defp build_direct_dependency(source_file, result) do
    dependency_type =
      cond do
        result.content =~ "import" -> :import
        result.content =~ "use" -> :use
        true -> :alias
      end

    %{
      source_file: source_file,
      dependent_file: result.file,
      dependency_type: dependency_type
    }
  end

  defp format_dependency_info(info) do
    sections = []

    sections =
      if info.direct != [] do
        deps = Enum.map(info.direct, &"#{&1.source_file} -> #{&1.dependent_file}")
        sections ++ ["Direct dependencies:\n#{Enum.join(deps, "\n")}"]
      else
        sections ++ ["No direct dependencies found"]
      end

    Enum.join(sections, "\n\n")
  end
end
