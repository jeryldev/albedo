defmodule Albedo.Tickets.Parser do
  @moduledoc """
  Parses ticket information from LLM output.

  Supports two formats:
  1. Structured JSON output (preferred) - Direct parsing with schema validation
  2. Markdown format (legacy) - Regex-based extraction from formatted text

  The JSON format provides 100% parsing reliability when LLMs follow the schema.
  """

  alias Albedo.Tickets.Schema
  alias Albedo.Tickets.Ticket

  @doc """
  Parse LLM output, automatically detecting format (JSON or markdown).
  """
  def parse(content) when is_binary(content) do
    content = String.trim(content)

    cond do
      json_content?(content) ->
        parse_json(content)

      markdown_content?(content) ->
        parse_markdown(content)

      true ->
        {:error, :unrecognized_format}
    end
  end

  def parse(_), do: {:error, :invalid_content}

  @doc """
  Parse structured JSON output from LLM.
  Returns {:ok, tickets} or {:error, reason}.
  """
  def parse_json(content) when is_binary(content) do
    json_content = extract_json(content)

    case Jason.decode(json_content) do
      {:ok, %{"tickets" => tickets}} when is_list(tickets) ->
        parsed_tickets = Enum.map(tickets, &parse_json_ticket/1)
        {:ok, parsed_tickets}

      {:ok, tickets} when is_list(tickets) ->
        parsed_tickets = Enum.map(tickets, &parse_json_ticket/1)
        {:ok, parsed_tickets}

      {:ok, _} ->
        {:error, :missing_tickets_array}

      {:error, reason} ->
        {:error, {:json_parse_error, reason}}
    end
  end

  @doc """
  Parse the full structured response including summary and metadata.
  Returns {:ok, response} with :summary, :tickets, :risks, etc.
  """
  def parse_structured_response(content) when is_binary(content) do
    json_content = extract_json(content)

    case Jason.decode(json_content) do
      {:ok, %{"tickets" => tickets} = response} when is_list(tickets) ->
        parsed = %{
          summary: parse_summary(response["summary"]),
          technical_overview: response["technical_overview"],
          tickets: Enum.map(tickets, &parse_json_ticket/1),
          implementation_order: response["implementation_order"] || [],
          risks: response["risks"] || [],
          effort_summary: parse_effort_summary(response["effort_summary"], tickets)
        }

        {:ok, parsed}

      {:ok, tickets} when is_list(tickets) ->
        {:ok,
         %{
           summary: nil,
           tickets: Enum.map(tickets, &parse_json_ticket/1),
           risks: [],
           effort_summary: calculate_effort_summary(tickets)
         }}

      {:ok, _} ->
        {:error, :missing_tickets_array}

      {:error, reason} ->
        {:error, {:json_parse_error, reason}}
    end
  end

  @doc """
  Parse legacy markdown format for backwards compatibility.
  """
  def parse_markdown(markdown_content) when is_binary(markdown_content) do
    ticket_sections = extract_ticket_sections(markdown_content)

    tickets =
      ticket_sections
      |> Enum.with_index(1)
      |> Enum.map(fn {section, index} ->
        parse_ticket_section(section, to_string(index))
      end)

    {:ok, tickets}
  end

  defp json_content?(content) do
    trimmed = String.trim(content)

    String.starts_with?(trimmed, "{") or
      String.starts_with?(trimmed, "[") or
      String.starts_with?(trimmed, "```json") or
      String.starts_with?(trimmed, "```\n{")
  end

  defp markdown_content?(content) do
    String.contains?(content, "### Ticket #") or
      String.contains?(content, "## Tickets") or
      String.contains?(content, "# ")
  end

  defp extract_json(content) do
    content = String.trim(content)

    cond do
      String.starts_with?(content, "```json") ->
        content
        |> String.replace(~r/^```json\s*/, "")
        |> String.replace(~r/```\s*$/, "")
        |> String.trim()

      String.starts_with?(content, "```") ->
        content
        |> String.replace(~r/^```\s*/, "")
        |> String.replace(~r/```\s*$/, "")
        |> String.trim()

      true ->
        content
    end
  end

  defp parse_json_ticket(ticket) when is_map(ticket) do
    Ticket.new(%{
      id: ticket["id"] || "0",
      title: ticket["title"] || "Untitled",
      description: ticket["description"],
      type: ticket["type"] || "feature",
      status: :pending,
      priority: ticket["priority"] || "medium",
      estimate: parse_estimate(ticket["estimate"]),
      labels: ticket["labels"] || [],
      acceptance_criteria: ticket["acceptance_criteria"] || [],
      implementation_notes: ticket["implementation_notes"],
      files: parse_files_from_json(ticket["files"]),
      dependencies: parse_dependencies_from_json(ticket["dependencies"])
    })
  end

  defp parse_estimate(est) when is_integer(est), do: est

  defp parse_estimate(est) when is_binary(est) do
    Schema.estimate_mapping()[String.downcase(est)]
  end

  defp parse_estimate(_), do: nil

  defp parse_files_from_json(files) when is_map(files) do
    %{
      create: files["create"] || [],
      modify: files["modify"] || []
    }
  end

  defp parse_files_from_json(_), do: %{create: [], modify: []}

  defp parse_dependencies_from_json(deps) when is_map(deps) do
    %{
      blocked_by: deps["blocked_by"] || [],
      blocks: deps["blocks"] || []
    }
  end

  defp parse_dependencies_from_json(_), do: %{blocked_by: [], blocks: []}

  defp parse_summary(nil), do: nil

  defp parse_summary(summary) when is_map(summary) do
    %{
      title: summary["title"],
      description: summary["description"],
      domain_context: summary["domain_context"] || [],
      in_scope: summary["in_scope"] || [],
      out_of_scope: summary["out_of_scope"] || [],
      assumptions: summary["assumptions"] || []
    }
  end

  defp parse_effort_summary(nil, tickets), do: calculate_effort_summary(tickets)

  defp parse_effort_summary(effort, _tickets) when is_map(effort) do
    %{
      total_tickets: effort["total_tickets"] || 0,
      total_points: effort["total_points"] || 0,
      breakdown: effort["breakdown"] || %{}
    }
  end

  defp calculate_effort_summary(tickets) do
    estimate_mapping = Schema.estimate_mapping()

    total_points =
      Enum.reduce(tickets, 0, fn ticket, acc ->
        case ticket["estimate"] do
          nil -> acc
          est when is_binary(est) -> acc + (estimate_mapping[String.downcase(est)] || 0)
          est when is_integer(est) -> acc + est
          _ -> acc
        end
      end)

    %{
      total_tickets: length(tickets),
      total_points: total_points,
      breakdown: %{}
    }
  end

  defp extract_ticket_sections(content) do
    pattern = ~r/### Ticket #\d+:(.*?)(?=### Ticket #\d+:|---\s*##|\z)/s

    Regex.scan(pattern, content, capture: :all_but_first)
    |> Enum.map(fn [section] -> String.trim(section) end)
  end

  defp parse_ticket_section(section, id) do
    title = extract_title(section)
    type = extract_field(section, "Type")
    priority = extract_field(section, "Priority")
    estimate = extract_field(section, "Estimate")
    depends_on = extract_field(section, "Depends On")
    blocks = extract_field(section, "Blocks")
    description = extract_section_content(section, "Description")
    implementation_notes = extract_section_content(section, "Implementation Notes")
    files_to_create = extract_table_files(section, "Files to Create")
    files_to_modify = extract_table_files(section, "Files to Modify")
    acceptance_criteria = extract_acceptance_criteria(section)
    labels = infer_labels(title, description, files_to_create, files_to_modify)

    Ticket.new(%{
      id: id,
      title: title,
      description: description,
      type: type,
      status: :pending,
      priority: priority,
      estimate: estimate,
      labels: labels,
      acceptance_criteria: acceptance_criteria,
      implementation_notes: implementation_notes,
      files: %{
        create: files_to_create,
        modify: files_to_modify
      },
      dependencies: %{
        blocked_by: parse_ticket_refs(depends_on),
        blocks: parse_ticket_refs(blocks)
      }
    })
  end

  defp extract_title(section) do
    lines = String.split(section, "\n", trim: true)
    first_line = List.first(lines) || ""
    String.trim(first_line)
  end

  defp extract_field(section, field_name) do
    pattern = ~r/\*\*#{Regex.escape(field_name)}:\*\*\s*(.+?)(?:\n|$)/i

    case Regex.run(pattern, section) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp extract_section_content(section, section_name) do
    pattern = ~r/####\s*#{Regex.escape(section_name)}\s*\n(.*?)(?=####|\z)/si

    case Regex.run(pattern, section) do
      [_, content] ->
        content
        |> String.trim()
        |> remove_table_if_present()

      _ ->
        nil
    end
  end

  defp remove_table_if_present(content) do
    if String.starts_with?(content, "|") do
      nil
    else
      content
    end
  end

  defp extract_table_files(section, table_name) do
    pattern = ~r/####\s*#{Regex.escape(table_name)}\s*\n\|[^\n]*\n\|[^\n]*\n((?:\|[^\n]*\n)*)/i

    case Regex.run(pattern, section) do
      [_, table_rows] ->
        table_rows
        |> String.split("\n", trim: true)
        |> Enum.map(&extract_file_from_row/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp extract_file_from_row(row) do
    cells = String.split(row, "|", trim: true)

    case cells do
      [file_path | _] ->
        path = String.trim(file_path)

        if path != "" and not String.starts_with?(path, "-") do
          clean_path(path)
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp clean_path(path) do
    path
    |> String.trim()
    |> String.replace(~r/^\`|\`$/, "")
    |> String.trim()
  end

  defp extract_acceptance_criteria(section) do
    pattern = ~r/####\s*Acceptance Criteria\s*\n(.*?)(?=####|\z)/si

    case Regex.run(pattern, section) do
      [_, content] ->
        content
        |> String.split("\n", trim: true)
        |> Enum.map(&extract_criterion/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp extract_criterion(line) do
    line = String.trim(line)

    cond do
      String.starts_with?(line, "- [ ]") ->
        String.replace(line, ~r/^-\s*\[\s*\]\s*/, "") |> String.trim()

      String.starts_with?(line, "- [x]") ->
        String.replace(line, ~r/^-\s*\[\s*x\s*\]\s*/i, "") |> String.trim()

      String.starts_with?(line, "-") ->
        String.replace(line, ~r/^-\s*/, "") |> String.trim()

      true ->
        nil
    end
  end

  defp parse_ticket_refs(nil), do: []
  defp parse_ticket_refs("None"), do: []
  defp parse_ticket_refs("none"), do: []

  defp parse_ticket_refs(refs) when is_binary(refs) do
    Regex.scan(~r/#(\d+)/, refs)
    |> Enum.map(fn [_, num] -> num end)
  end

  defp infer_labels(title, description, files_create, files_modify) do
    all_text = "#{title} #{description}"
    all_files = files_create ++ files_modify

    label_rules = [
      {"backend",
       fn ->
         has_pattern?(all_files, ~r/\.ex$/) and
           not has_pattern?(all_files, ~r/_live\.ex$|_controller\.ex$/)
       end},
      {"liveview", fn -> has_pattern?(all_files, ~r/_live\.ex$|\.heex$/) end},
      {"frontend", fn -> has_pattern?(all_files, ~r/_controller\.ex$|\.html\./) end},
      {"database", fn -> has_pattern?(all_files, ~r/migrations?\/|schema\.ex$/) end},
      {"test", fn -> has_pattern?(all_files, ~r/_test\.exs?$/) end},
      {"auth", fn -> has_pattern?(all_text, ~r/auth|login|password|token/i) end}
    ]

    label_rules
    |> Enum.filter(fn {_label, check_fn} -> check_fn.() end)
    |> Enum.map(fn {label, _} -> label end)
    |> Enum.uniq()
  end

  defp has_pattern?(list, pattern) when is_list(list) do
    Enum.any?(list, &Regex.match?(pattern, &1))
  end

  defp has_pattern?(text, pattern) when is_binary(text) do
    Regex.match?(pattern, text)
  end
end
