defmodule Albedo.Tickets.Parser do
  @moduledoc """
  Parses ticket information from FEATURE.md markdown content.
  Extracts structured ticket data from the LLM-generated markdown format.
  """

  alias Albedo.Tickets.Ticket

  def parse(markdown_content) when is_binary(markdown_content) do
    ticket_sections = extract_ticket_sections(markdown_content)

    tickets =
      ticket_sections
      |> Enum.with_index(1)
      |> Enum.map(fn {section, index} ->
        parse_ticket_section(section, to_string(index))
      end)

    {:ok, tickets}
  end

  def parse(_), do: {:error, :invalid_content}

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
      {"auth", fn -> has_pattern?(all_text, ~r/auth|login|session|password|token/i) end}
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
