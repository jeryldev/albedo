defmodule Albedo.Tickets.Ticket do
  @moduledoc """
  Ticket struct representing a single work item.
  Designed for CLI display and export to external systems (Linear, Jira, GitHub Issues, Asana).
  """

  @enforce_keys [:id, :title]
  defstruct [
    :id,
    :title,
    :description,
    :type,
    :status,
    :priority,
    :estimate,
    :labels,
    :acceptance_criteria,
    :implementation_notes,
    :files,
    :dependencies,
    :external_refs,
    :timestamps
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          description: String.t() | nil,
          type: ticket_type(),
          status: status(),
          priority: priority(),
          estimate: pos_integer() | nil,
          labels: [String.t()],
          acceptance_criteria: [String.t()],
          implementation_notes: String.t() | nil,
          files: files(),
          dependencies: dependencies(),
          external_refs: external_refs(),
          timestamps: timestamps()
        }

  @type ticket_type :: :feature | :enhancement | :bugfix | :chore | :docs | :test
  @type status :: :pending | :in_progress | :completed
  @type priority :: :urgent | :high | :medium | :low | :none

  @type files :: %{
          create: [String.t()],
          modify: [String.t()]
        }

  @type dependencies :: %{
          blocked_by: [String.t()],
          blocks: [String.t()]
        }

  @type external_refs :: %{
          linear: String.t() | nil,
          jira: String.t() | nil,
          github: String.t() | nil,
          asana: String.t() | nil
        }

  @type timestamps :: %{
          created_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil
        }

  @statuses [:pending, :in_progress, :completed]
  @types [:feature, :enhancement, :bugfix, :chore, :docs, :test]
  @priorities [:urgent, :high, :medium, :low, :none]

  @estimate_map %{
    "trivial" => 1,
    "small" => 2,
    "medium" => 3,
    "large" => 5,
    "extra large" => 8,
    "epic" => 13
  }

  @priority_map %{
    "urgent" => :urgent,
    "high" => :high,
    "medium" => :medium,
    "low" => :low,
    "none" => :none
  }

  @type_map %{
    "task" => :feature,
    "story" => :feature,
    "feature" => :feature,
    "enhancement" => :enhancement,
    "bug" => :bugfix,
    "bugfix" => :bugfix,
    "chore" => :chore,
    "docs" => :docs,
    "documentation" => :docs,
    "test" => :test
  }

  def statuses, do: @statuses
  def types, do: @types
  def priorities, do: @priorities

  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    %__MODULE__{
      id: Map.get(attrs, :id) || Map.get(attrs, "id"),
      title: Map.get(attrs, :title) || Map.get(attrs, "title"),
      description: Map.get(attrs, :description) || Map.get(attrs, "description"),
      type: parse_type(Map.get(attrs, :type) || Map.get(attrs, "type")),
      status: parse_status(Map.get(attrs, :status) || Map.get(attrs, "status")),
      priority: parse_priority(Map.get(attrs, :priority) || Map.get(attrs, "priority")),
      estimate: parse_estimate(Map.get(attrs, :estimate) || Map.get(attrs, "estimate")),
      labels: parse_labels(Map.get(attrs, :labels) || Map.get(attrs, "labels")),
      acceptance_criteria:
        List.wrap(
          Map.get(attrs, :acceptance_criteria) || Map.get(attrs, "acceptance_criteria") || []
        ),
      implementation_notes:
        Map.get(attrs, :implementation_notes) || Map.get(attrs, "implementation_notes"),
      files: parse_files(Map.get(attrs, :files) || Map.get(attrs, "files")),
      dependencies:
        parse_dependencies(Map.get(attrs, :dependencies) || Map.get(attrs, "dependencies")),
      external_refs: %{linear: nil, jira: nil, github: nil, asana: nil},
      timestamps: %{
        created_at: now,
        started_at: nil,
        completed_at: nil
      }
    }
  end

  def start(%__MODULE__{status: :pending} = ticket) do
    %{
      ticket
      | status: :in_progress,
        timestamps: %{ticket.timestamps | started_at: DateTime.utc_now()}
    }
  end

  def start(%__MODULE__{} = ticket), do: ticket

  def complete(%__MODULE__{} = ticket) do
    now = DateTime.utc_now()
    started_at = ticket.timestamps.started_at || now

    %{
      ticket
      | status: :completed,
        timestamps: %{ticket.timestamps | started_at: started_at, completed_at: now}
    }
  end

  def reset(%__MODULE__{} = ticket) do
    %{
      ticket
      | status: :pending,
        timestamps: %{ticket.timestamps | started_at: nil, completed_at: nil}
    }
  end

  def edit(%__MODULE__{} = ticket, changes) when is_map(changes) do
    ticket
    |> maybe_update_priority(changes[:priority])
    |> maybe_update_estimate(changes[:points])
  end

  defp maybe_update_priority(ticket, nil), do: ticket

  defp maybe_update_priority(ticket, priority) when is_atom(priority) do
    if priority in @priorities do
      %{ticket | priority: priority}
    else
      ticket
    end
  end

  defp maybe_update_priority(ticket, priority) when is_binary(priority) do
    case @priority_map[String.downcase(priority)] do
      nil -> ticket
      parsed -> %{ticket | priority: parsed}
    end
  end

  defp maybe_update_estimate(ticket, nil), do: ticket

  defp maybe_update_estimate(ticket, points) when is_integer(points) and points > 0 do
    %{ticket | estimate: points}
  end

  defp maybe_update_estimate(ticket, _), do: ticket

  def to_json(%__MODULE__{} = ticket) do
    %{
      "id" => ticket.id,
      "title" => ticket.title,
      "description" => ticket.description,
      "type" => to_string(ticket.type),
      "status" => to_string(ticket.status),
      "priority" => to_string(ticket.priority),
      "estimate" => ticket.estimate,
      "labels" => ticket.labels,
      "acceptance_criteria" => ticket.acceptance_criteria,
      "implementation_notes" => ticket.implementation_notes,
      "files" => files_to_json(ticket.files),
      "dependencies" => dependencies_to_json(ticket.dependencies),
      "external_refs" => external_refs_to_json(ticket.external_refs),
      "timestamps" => timestamps_to_json(ticket.timestamps)
    }
  end

  def from_json(json) when is_map(json) do
    %__MODULE__{
      id: json["id"],
      title: json["title"],
      description: json["description"],
      type: String.to_existing_atom(json["type"] || "feature"),
      status: String.to_existing_atom(json["status"] || "pending"),
      priority: String.to_existing_atom(json["priority"] || "medium"),
      estimate: json["estimate"],
      labels: json["labels"] || [],
      acceptance_criteria: json["acceptance_criteria"] || [],
      implementation_notes: json["implementation_notes"],
      files: parse_files(json["files"]),
      dependencies: parse_dependencies(json["dependencies"]),
      external_refs: parse_external_refs(json["external_refs"]),
      timestamps: parse_timestamps(json["timestamps"])
    }
  end

  defp parse_type(nil), do: :feature
  defp parse_type(type) when is_atom(type) and type in @types, do: type
  defp parse_type(type) when is_binary(type), do: @type_map[String.downcase(type)] || :feature

  defp parse_status(nil), do: :pending
  defp parse_status(status) when is_atom(status) and status in @statuses, do: status

  defp parse_status(status) when is_binary(status) do
    case String.downcase(status) do
      "pending" -> :pending
      "in_progress" -> :in_progress
      "completed" -> :completed
      _ -> :pending
    end
  end

  defp parse_priority(nil), do: :medium
  defp parse_priority(priority) when is_atom(priority) and priority in @priorities, do: priority

  defp parse_priority(priority) when is_binary(priority),
    do: @priority_map[String.downcase(priority)] || :medium

  defp parse_estimate(nil), do: nil
  defp parse_estimate(est) when is_integer(est), do: est
  defp parse_estimate(est) when is_binary(est), do: @estimate_map[String.downcase(est)]

  defp parse_labels(nil), do: []
  defp parse_labels(labels) when is_list(labels), do: labels

  defp parse_labels(labels) when is_binary(labels),
    do: String.split(labels, ~r/[,\s]+/, trim: true)

  defp parse_files(nil), do: %{create: [], modify: []}
  defp parse_files(%{"create" => c, "modify" => m}), do: %{create: c || [], modify: m || []}
  defp parse_files(%{create: c, modify: m}), do: %{create: c || [], modify: m || []}
  defp parse_files(_), do: %{create: [], modify: []}

  defp parse_dependencies(nil), do: %{blocked_by: [], blocks: []}

  defp parse_dependencies(%{"blocked_by" => by, "blocks" => b}),
    do: %{blocked_by: by || [], blocks: b || []}

  defp parse_dependencies(%{blocked_by: by, blocks: b}),
    do: %{blocked_by: by || [], blocks: b || []}

  defp parse_dependencies(_), do: %{blocked_by: [], blocks: []}

  defp parse_external_refs(nil), do: %{linear: nil, jira: nil, github: nil, asana: nil}

  defp parse_external_refs(refs) when is_map(refs) do
    %{
      linear: refs["linear"] || refs[:linear],
      jira: refs["jira"] || refs[:jira],
      github: refs["github"] || refs[:github],
      asana: refs["asana"] || refs[:asana]
    }
  end

  defp parse_timestamps(nil) do
    %{created_at: DateTime.utc_now(), started_at: nil, completed_at: nil}
  end

  defp parse_timestamps(ts) when is_map(ts) do
    %{
      created_at: parse_datetime(ts["created_at"] || ts[:created_at]) || DateTime.utc_now(),
      started_at: parse_datetime(ts["started_at"] || ts[:started_at]),
      completed_at: parse_datetime(ts["completed_at"] || ts[:completed_at])
    }
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp files_to_json(files) do
    %{"create" => files.create, "modify" => files.modify}
  end

  defp dependencies_to_json(deps) do
    %{"blocked_by" => deps.blocked_by, "blocks" => deps.blocks}
  end

  defp external_refs_to_json(refs) do
    %{
      "linear" => refs.linear,
      "jira" => refs.jira,
      "github" => refs.github,
      "asana" => refs.asana
    }
  end

  defp timestamps_to_json(ts) do
    %{
      "created_at" => format_datetime(ts.created_at),
      "started_at" => format_datetime(ts.started_at),
      "completed_at" => format_datetime(ts.completed_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
