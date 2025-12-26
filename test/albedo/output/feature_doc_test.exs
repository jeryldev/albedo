defmodule Albedo.Output.FeatureDocTest do
  use ExUnit.Case, async: true

  alias Albedo.Output.FeatureDoc

  describe "generate/1" do
    test "generates complete document with all sections" do
      state = build_complete_state()
      result = FeatureDoc.generate(state)

      assert result =~ "# Feature: Add user authentication"
      assert result =~ "## Executive Summary"
      assert result =~ "## Domain Context"
      assert result =~ "## Technical Overview"
      assert result =~ "## Tickets"
      assert result =~ "## Dependency Graph"
      assert result =~ "## Implementation Order"
      assert result =~ "## Risk Summary"
      assert result =~ "## Estimated Total Effort"
      assert result =~ "## Appendix"
    end

    test "generates document with minimal state" do
      state = build_minimal_state()
      result = FeatureDoc.generate(state)

      assert result =~ "# Feature: Simple task"
      assert result =~ "N/A"
    end
  end

  describe "header generation" do
    test "includes task name" do
      header = generate_header(%{task: "Add feature X", project_dir: "/path/to/project"})
      assert header =~ "# Feature: Add feature X"
    end

    test "includes Albedo version" do
      header = generate_header(%{task: "Task", project_dir: "/path"})
      assert header =~ "Albedo v"
    end

    test "includes current date" do
      header = generate_header(%{task: "Task", project_dir: "/path"})
      assert header =~ Date.utc_today() |> to_string()
    end

    test "includes project directory" do
      header = generate_header(%{task: "Task", project_dir: "/path/to/my-project"})
      assert header =~ "/path/to/my-project"
    end
  end

  describe "executive summary generation" do
    test "includes ticket count" do
      summary = generate_executive_summary(%{summary: %{tickets_count: 5}})
      assert summary =~ "Tickets:** 5"
    end

    test "includes total points" do
      summary = generate_executive_summary(%{summary: %{total_points: 21}})
      assert summary =~ "Points:** 21"
    end

    test "includes files to create" do
      summary = generate_executive_summary(%{summary: %{files_to_create: 3}})
      assert summary =~ "Files to Create:** 3"
    end

    test "includes files to modify" do
      summary = generate_executive_summary(%{summary: %{files_to_modify: 7}})
      assert summary =~ "Files to Modify:** 7"
    end

    test "includes risks identified" do
      summary = generate_executive_summary(%{summary: %{risks_identified: 2}})
      assert summary =~ "Risks Identified:** 2"
    end

    test "shows N/A for missing summary" do
      summary = generate_executive_summary(%{summary: nil})
      assert summary =~ "N/A"
    end
  end

  describe "key points extraction" do
    test "extracts bullet points from content" do
      content = """
      # Title
      - Point one
      - Point two
      - Point three
      - Point four
      - Point five
      - Point six
      """

      result = extract_key_points(content, 3)
      assert result =~ "Point one"
      assert result =~ "Point two"
      assert result =~ "Point three"
      refute result =~ "Point four"
    end

    test "returns empty for content without bullet points" do
      result = extract_key_points("No bullet points here", 5)
      assert result == ""
    end

    test "returns message for nil content" do
      result = extract_key_points(nil, 5)
      assert result =~ "No domain research available"
    end
  end

  describe "section summarization" do
    test "returns full content if under max length" do
      content = "Short content"
      result = summarize_section(content, 100)
      assert result == "Short content"
    end

    test "truncates content over max length" do
      content = String.duplicate("a", 500)
      result = summarize_section(content, 100)
      assert String.length(result) == 103
      assert String.ends_with?(result, "...")
    end

    test "returns message for nil content" do
      result = summarize_section(nil, 100)
      assert result == "Not available."
    end
  end

  describe "tickets section extraction" do
    test "extracts tickets starting from first ticket" do
      content = """
      ## Overview
      Some overview text.

      ### Ticket #1: Create schema
      Description here.

      ### Ticket #2: Add routes
      More content.
      """

      result = extract_tickets_section(content)
      assert result =~ "Ticket #1"
      assert result =~ "Ticket #2"
      refute result =~ "## Overview"
    end

    test "returns full content if no ticket markers found" do
      content = "Content without ticket markers"
      result = extract_tickets_section(content)
      assert result == content
    end

    test "returns message for nil content" do
      result = extract_tickets_section(nil)
      assert result =~ "No tickets available"
    end
  end

  describe "questions formatting" do
    test "formats questions with answers" do
      questions = [
        %{question: "What is the scope?", answer: "User module only"},
        %{question: "Should we add tests?", answer: "Yes"}
      ]

      result = format_questions(questions)
      assert result =~ "1. What is the scope? → User module only"
      assert result =~ "2. Should we add tests? → Yes"
    end

    test "shows pending for questions without answers" do
      questions = [%{question: "Pending question?", answer: nil}]
      result = format_questions(questions)
      assert result =~ "Pending question? → Pending"
    end

    test "returns message for empty questions list" do
      result = format_questions([])
      assert result =~ "No clarifying questions were asked"
    end
  end

  defp build_complete_state do
    %{
      task: "Add user authentication",
      project_dir: "/tmp/project-123",
      summary: %{
        tickets_count: 5,
        total_points: 21,
        files_to_create: 3,
        files_to_modify: 7,
        risks_identified: 2
      },
      context: %{
        domain_research: %{content: "- Key point 1\n- Key point 2"},
        tech_stack: %{content: "Elixir/Phoenix application"},
        architecture: %{content: "Standard Phoenix structure"},
        change_planning: %{content: "### Ticket #1: Setup\n\nDescription"}
      },
      clarifying_questions: [
        %{question: "Auth method?", answer: "Token-based"}
      ]
    }
  end

  defp build_minimal_state do
    %{
      task: "Simple task",
      project_dir: "/tmp/minimal",
      summary: nil,
      context: %{},
      clarifying_questions: []
    }
  end

  defp generate_header(state) do
    """
    # Feature: #{state.task}

    **Generated by:** Albedo v#{Albedo.version()}
    **Date:** #{Date.utc_today()}
    **Project:** #{state.project_dir}
    """
  end

  defp generate_executive_summary(state) do
    summary = state.summary || %{}

    """
    ## Executive Summary

    This document contains the implementation plan for the requested feature.

    - **Tickets:** #{summary[:tickets_count] || "N/A"}
    - **Estimated Points:** #{summary[:total_points] || "N/A"}
    - **Files to Create:** #{summary[:files_to_create] || "N/A"}
    - **Files to Modify:** #{summary[:files_to_modify] || "N/A"}
    - **Risks Identified:** #{summary[:risks_identified] || "N/A"}
    """
  end

  defp extract_key_points(content, count) when is_binary(content) do
    content
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "- "))
    |> Enum.take(count)
    |> Enum.join("\n")
  end

  defp extract_key_points(_, _), do: "No domain research available."

  defp summarize_section(nil, _), do: "Not available."

  defp summarize_section(content, max_length) when is_binary(content) do
    if String.length(content) > max_length do
      String.slice(content, 0, max_length) <> "..."
    else
      content
    end
  end

  defp extract_tickets_section(content) when is_binary(content) do
    case Regex.run(~r/(### Ticket #1.*)/s, content) do
      [_, tickets] -> tickets
      _ -> content
    end
  end

  defp extract_tickets_section(_), do: "No tickets available."

  defp format_questions([]), do: "No clarifying questions were asked."

  defp format_questions(questions) do
    questions
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {q, idx} ->
      "#{idx}. #{q[:question]} → #{q[:answer] || "Pending"}"
    end)
  end
end
