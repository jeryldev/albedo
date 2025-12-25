defmodule Albedo.Tickets.Exporters.Markdown do
  @moduledoc """
  Exports tickets to Markdown checklist format.
  Human-readable format suitable for documentation and task tracking.
  """

  @behaviour Albedo.Tickets.Exporter

  alias Albedo.Tickets.Exporter

  @impl true
  def export(tickets_data, opts \\ []) do
    tickets = Exporter.filter_by_status(tickets_data.tickets, opts)

    content = """
    # #{tickets_data.task_description || "Tickets"}

    **Session:** #{tickets_data.session_id}
    #{if tickets_data.project_name, do: "**Project:** #{tickets_data.project_name}\n", else: ""}
    ## Summary

    | Status | Count |
    |--------|-------|
    | Pending | #{Enum.count(tickets, &(&1.status == :pending))} |
    | In Progress | #{Enum.count(tickets, &(&1.status == :in_progress))} |
    | Completed | #{Enum.count(tickets, &(&1.status == :completed))} |
    | **Total** | **#{length(tickets)}** |

    ---

    ## Tickets

    #{format_tickets(tickets)}
    """

    {:ok, String.trim(content)}
  end

  @impl true
  def file_extension, do: ".md"

  @impl true
  def format_name, do: "Markdown"

  defp format_tickets(tickets) do
    Enum.map_join(tickets, "\n---\n\n", &format_ticket/1)
  end

  defp format_ticket(ticket) do
    checkbox = status_checkbox(ticket.status)
    priority_badge = priority_badge(ticket.priority)
    estimate_str = if ticket.estimate, do: " (#{ticket.estimate} pts)", else: ""

    sections = [
      "### #{checkbox} #{ticket.title}",
      "",
      "#{priority_badge} **#{ticket.type}**#{estimate_str}",
      ""
    ]

    sections =
      if ticket.description do
        sections ++ [ticket.description, ""]
      else
        sections
      end

    sections =
      if ticket.labels != [] do
        labels = Enum.map_join(ticket.labels, " ", &"`#{&1}`")
        sections ++ ["**Labels:** #{labels}", ""]
      else
        sections
      end

    sections =
      if ticket.files.create != [] do
        files = Enum.map_join(ticket.files.create, "\n", &"  - `#{&1}`")
        sections ++ ["**Files to Create:**", files, ""]
      else
        sections
      end

    sections =
      if ticket.files.modify != [] do
        files = Enum.map_join(ticket.files.modify, "\n", &"  - `#{&1}`")
        sections ++ ["**Files to Modify:**", files, ""]
      else
        sections
      end

    sections =
      if ticket.acceptance_criteria != [] do
        criteria =
          ticket.acceptance_criteria
          |> Enum.map(&String.replace(&1, ~r/^\s*\[[ x~]\]\s*/, ""))
          |> Enum.map_join("\n", &"- [ ] #{&1}")

        sections ++ ["**Acceptance Criteria:**", criteria, ""]
      else
        sections
      end

    sections =
      if ticket.dependencies.blocked_by != [] do
        deps = Enum.map_join(ticket.dependencies.blocked_by, ", ", &"##{&1}")
        sections ++ ["**Blocked by:** #{deps}", ""]
      else
        sections
      end

    sections =
      if ticket.dependencies.blocks != [] do
        deps = Enum.map_join(ticket.dependencies.blocks, ", ", &"##{&1}")
        sections ++ ["**Blocks:** #{deps}", ""]
      else
        sections
      end

    Enum.join(sections, "\n")
  end

  defp status_checkbox(:completed), do: "[x]"
  defp status_checkbox(:in_progress), do: "[~]"
  defp status_checkbox(:pending), do: "[ ]"

  defp priority_badge(:urgent), do: "🔴"
  defp priority_badge(:high), do: "🟠"
  defp priority_badge(:medium), do: "🟡"
  defp priority_badge(:low), do: "🟢"
  defp priority_badge(:none), do: "⚪"
end
