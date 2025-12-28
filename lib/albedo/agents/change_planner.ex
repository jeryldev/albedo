defmodule Albedo.Agents.ChangePlanner do
  @moduledoc """
  Phase 4: Change Planning Agent.
  Generates concrete, actionable tickets based on all previous research.

  Uses structured JSON output by default for reliable parsing.
  Falls back to markdown parsing for legacy responses.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts
  alias Albedo.Tickets.Parser

  defp get_flexible_key(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp get_flexible_key(_, _), do: nil

  @impl Albedo.Agents.Base
  def investigate(state) do
    task = state.task
    context = state.context
    greenfield? = context[:greenfield] || false
    use_structured? = context[:structured_output] != false

    prompt =
      if use_structured? do
        Prompts.change_planning_structured(task, context)
      else
        Prompts.change_planning(task, context)
      end

    case call_llm(prompt, max_tokens: 16_384) do
      {:ok, response} ->
        process_response(response, greenfield?, use_structured?)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_response(response, greenfield?, true = _use_structured?) do
    case Parser.parse_structured_response(response) do
      {:ok, parsed} ->
        build_findings_from_structured(response, parsed, greenfield?)

      {:error, _reason} ->
        process_response(response, greenfield?, false)
    end
  end

  defp process_response(response, greenfield?, false = _use_structured?) do
    tickets = parse_tickets(response)
    tickets_count = length(tickets)
    total_points = calculate_total_points(tickets)
    summary = extract_summary_from_markdown(response)

    findings = %{
      content: response,
      tickets: tickets,
      tickets_count: tickets_count,
      total_points: total_points,
      files_to_create: summary.files_to_create,
      files_to_modify: summary.files_to_modify,
      risks_identified: summary.risks_identified,
      greenfield: greenfield?
    }

    {:ok, findings}
  end

  defp build_findings_from_structured(response, parsed, greenfield?) do
    tickets = parsed.tickets
    tickets_count = length(tickets)
    total_points = calculate_total_points(tickets)

    files_to_create = count_files_from_tickets(tickets, :create)
    files_to_modify = count_files_from_tickets(tickets, :modify)
    risks_identified = length(parsed.risks || [])

    content = format_structured_as_markdown(parsed, response)

    findings = %{
      content: content,
      tickets: tickets,
      tickets_count: tickets_count,
      total_points: total_points,
      files_to_create: files_to_create,
      files_to_modify: files_to_modify,
      risks_identified: risks_identified,
      greenfield: greenfield?,
      structured_response: parsed
    }

    {:ok, findings}
  end

  defp calculate_total_points(tickets) do
    tickets
    |> Enum.map(& &1.estimate)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  defp count_files_from_tickets(tickets, type) do
    tickets
    |> Enum.flat_map(fn ticket ->
      case type do
        :create -> ticket.files.create || []
        :modify -> ticket.files.modify || []
      end
    end)
    |> Enum.uniq()
    |> length()
  end

  defp format_structured_as_markdown(parsed, original_json) do
    summary_section = format_summary_section(parsed.summary)
    overview_section = format_overview_section(parsed.technical_overview)
    tickets_section = format_tickets_section(parsed.tickets)
    risks_section = format_risks_section(parsed.risks)
    order_section = format_order_section(parsed.implementation_order)

    """
    #{summary_section}

    #{overview_section}

    ---

    ## Tickets

    #{tickets_section}

    ---

    #{order_section}

    #{risks_section}

    ## Effort Summary

    | Category | Count |
    |----------|-------|
    | Total Tickets | #{length(parsed.tickets)} |
    | Total Points | #{calculate_total_points(parsed.tickets)} |

    ---

    <details>
    <summary>Raw JSON Response</summary>

    ```json
    #{original_json}
    ```

    </details>
    """
  end

  defp format_summary_section(nil), do: ""

  defp format_summary_section(summary) do
    domain_context =
      if summary.domain_context and summary.domain_context != [] do
        "## Domain Context\n" <>
          Enum.map_join(summary.domain_context, "\n", &"- #{&1}")
      else
        ""
      end

    in_scope =
      if summary.in_scope and summary.in_scope != [] do
        "### In Scope\n" <> Enum.map_join(summary.in_scope, "\n", &"- #{&1}")
      else
        ""
      end

    out_of_scope =
      if summary.out_of_scope and summary.out_of_scope != [] do
        "### Out of Scope\n" <> Enum.map_join(summary.out_of_scope, "\n", &"- #{&1}")
      else
        ""
      end

    """
    # Feature: #{summary.title || "Untitled"}

    ## Executive Summary
    #{summary.description || ""}

    #{domain_context}

    ## Scope

    #{in_scope}

    #{out_of_scope}
    """
  end

  defp format_overview_section(nil), do: ""

  defp format_overview_section(overview) when is_map(overview) do
    key_changes =
      case get_flexible_key(overview, :key_changes) do
        nil ->
          ""

        changes ->
          Enum.with_index(changes, 1) |> Enum.map_join("\n", fn {c, i} -> "#{i}. #{c}" end)
      end

    """
    ## Technical Overview

    ### Current State
    #{get_flexible_key(overview, :current_state) || "N/A"}

    ### Target State
    #{get_flexible_key(overview, :target_state) || "N/A"}

    ### Key Changes
    #{key_changes}
    """
  end

  defp format_tickets_section(tickets) do
    Enum.map_join(tickets, "\n\n---\n\n", &format_single_ticket/1)
  end

  defp format_single_ticket(ticket) do
    """
    ### Ticket ##{ticket.id}: #{ticket.title}

    **Type:** #{ticket.type |> to_string() |> String.capitalize()}
    **Priority:** #{ticket.priority |> to_string() |> String.capitalize()}
    **Estimate:** #{format_estimate(ticket.estimate)}
    **Depends On:** #{format_deps(ticket.dependencies.blocked_by, "None")}
    **Blocks:** #{format_deps(ticket.dependencies.blocks, "")}

    #### Description
    #{ticket.description || "No description"}

    #### Implementation Notes
    #{ticket.implementation_notes || "No implementation notes"}

    #{format_files_table(ticket.files.create, "Files to Create", "Purpose")}

    #{format_files_table(ticket.files.modify, "Files to Modify", "Changes")}

    #{format_acceptance_criteria(ticket.acceptance_criteria)}
    """
  end

  @estimate_labels %{
    1 => "Trivial",
    2 => "Small",
    3 => "Medium",
    5 => "Large",
    8 => "Extra Large",
    13 => "Epic"
  }

  defp format_estimate(nil), do: "Not estimated"
  defp format_estimate(n), do: Map.get(@estimate_labels, n, "#{n} points")

  defp format_deps([], default), do: default
  defp format_deps(deps, _default), do: Enum.map_join(deps, ", ", &"##{&1}")

  defp format_files_table(input, _, _) when input in [nil, []], do: ""

  defp format_files_table(files, title, col) do
    "#### #{title}\n| File | #{col} |\n|------|--------|\n" <>
      Enum.map_join(files, "\n", &"| #{&1} | |")
  end

  defp format_acceptance_criteria(input) when input in [nil, []], do: ""

  defp format_acceptance_criteria(criteria) do
    "#### Acceptance Criteria\n" <> Enum.map_join(criteria, "\n", &"- [ ] #{&1}")
  end

  defp format_risks_section([]), do: ""

  defp format_risks_section(risks) when is_list(risks) do
    rows = Enum.map_join(risks, "\n", &format_risk_row/1)

    """
    ## Risk Summary

    | Risk | Likelihood | Impact | Mitigation |
    |------|------------|--------|------------|
    #{rows}
    """
  end

  defp format_risks_section(_), do: ""

  defp format_risk_row(risk) do
    "| #{get_flexible_key(risk, :risk) || ""} | #{get_flexible_key(risk, :likelihood) || ""} | #{get_flexible_key(risk, :impact) || ""} | #{get_flexible_key(risk, :mitigation) || ""} |"
  end

  defp format_order_section([]), do: ""

  defp format_order_section(order) when is_list(order) do
    items =
      order
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {item, idx} ->
        "#{idx}. **##{get_flexible_key(item, :ticket_id)}** - #{get_flexible_key(item, :reason) || ""}"
      end)

    """
    ## Implementation Order

    #{items}
    """
  end

  defp format_order_section(_), do: ""

  defp parse_tickets(content) do
    case Parser.parse(content) do
      {:ok, tickets} ->
        tickets

      {:error, reason} ->
        Logger.warning("Failed to parse LLM response for tickets: #{inspect(reason)}")
        []
    end
  end

  @impl Albedo.Agents.Base
  def format_output(findings) do
    add_metadata_header(findings.content, findings[:greenfield] || false)
  end

  defp add_metadata_header(content, greenfield?) do
    """
    <!-- Generated by Albedo v#{Albedo.version()} on #{Date.utc_today()} -->

    #{content}

    ---

    ## Appendix

    ### Research Files
    All research that informed this plan:

    #{research_files_list(greenfield?)}
    """
  end

  defp research_files_list(true) do
    """
    - [00_domain_research.md](./00_domain_research.md)
    - [01_tech_stack.md](./01_tech_stack.md)
    - [02_architecture.md](./02_architecture.md)
    """
  end

  defp research_files_list(false) do
    """
    - [00_domain_research.md](./00_domain_research.md)
    - [01_tech_stack.md](./01_tech_stack.md)
    - [02_architecture.md](./02_architecture.md)
    - [03_conventions.md](./03_conventions.md)
    - [04_feature_location.md](./04_feature_location.md)
    - [05_impact_analysis.md](./05_impact_analysis.md)
    """
  end

  defp extract_summary_from_markdown(content) do
    tickets_count = count_tickets(content)
    total_points = extract_total_points(content)
    files_to_create = count_files_to_create(content)
    files_to_modify = count_files_to_modify(content)
    risks_identified = count_risks(content)

    %{
      tickets_count: tickets_count,
      total_points: total_points,
      files_to_create: files_to_create,
      files_to_modify: files_to_modify,
      risks_identified: risks_identified
    }
  end

  defp count_tickets(content) do
    Regex.scan(~r/### Ticket #\d+/, content)
    |> length()
  end

  defp extract_total_points(content) do
    case Regex.run(~r/\*\*Total\*\*.*?(\d+)/, content) do
      [_, points] -> String.to_integer(points)
      _ -> estimate_points(content)
    end
  end

  defp estimate_points(content) do
    small = length(Regex.scan(~r/Estimate.*Small/i, content)) * 2
    medium = length(Regex.scan(~r/Estimate.*Medium/i, content)) * 5
    large = length(Regex.scan(~r/Estimate.*Large/i, content)) * 8
    small + medium + large
  end

  defp count_files_to_create(content) do
    sections = Regex.scan(~r/#### Files to Create\n\|.*?\n\|.*?\n((?:\|.*?\n)*)/s, content)

    sections
    |> Enum.flat_map(fn [_, table] ->
      String.split(table, "\n", trim: true)
    end)
    |> Enum.filter(&String.starts_with?(&1, "|"))
    |> length()
  end

  defp count_files_to_modify(content) do
    sections = Regex.scan(~r/#### Files to Modify\n\|.*?\n\|.*?\n((?:\|.*?\n)*)/s, content)

    sections
    |> Enum.flat_map(fn [_, table] ->
      String.split(table, "\n", trim: true)
    end)
    |> Enum.filter(&String.starts_with?(&1, "|"))
    |> length()
  end

  defp count_risks(content) do
    risk_section =
      Regex.run(~r/## Risk Summary\n\n\|.*?\n\|.*?\n((?:\|.*?\n)*)/s, content)

    case risk_section do
      [_, table] ->
        table
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.starts_with?(&1, "|"))
        |> length()

      _ ->
        length(Regex.scan(~r/\| High \||\| Medium \|/i, content))
    end
  end
end
