defmodule Albedo.Tickets.Ticket do
  @moduledoc """
  Ticket struct representing a single work item.
  Designed for CLI display and export to external systems (Linear, Jira, GitHub Issues, Asana).

  Uses schemaless changeset patterns for consistent validation and casting.
  """

  alias Albedo.Changeset

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

  @type_mapping %{
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

  @priority_mapping %{
    "urgent" => :urgent,
    "high" => :high,
    "medium" => :medium,
    "low" => :low,
    "none" => :none
  }

  @status_mapping %{
    "pending" => :pending,
    "in_progress" => :in_progress,
    "completed" => :completed
  }

  @estimate_mapping %{
    "trivial" => 1,
    "small" => 2,
    "medium" => 3,
    "large" => 5,
    "extra large" => 8,
    "epic" => 13
  }

  @types_schema %{
    id: :string,
    title: :string,
    description: :string,
    type: {:enum, @types, @type_mapping},
    status: {:enum, @statuses, @status_mapping},
    priority: {:enum, @priorities, @priority_mapping},
    estimate: :integer,
    labels: :list,
    acceptance_criteria: :list,
    implementation_notes: :string
  }

  @edit_fields [:title, :description, :type, :status, :priority, :estimate, :labels]

  def statuses, do: @statuses
  def types, do: @types
  def priorities, do: @priorities

  @doc """
  Creates a new ticket from attributes.
  Uses changeset for casting and validation.

  ## Examples

      iex> Ticket.new(%{id: "1", title: "Fix bug"})
      %Ticket{id: "1", title: "Fix bug", status: :pending, ...}

      iex> Ticket.new(%{"id" => "1", "title" => "Fix bug", "priority" => "high"})
      %Ticket{id: "1", title: "Fix bug", priority: :high, ...}
  """
  def new(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    changeset =
      {defaults(), @types_schema}
      |> Changeset.cast(attrs, Map.keys(@types_schema))
      |> cast_estimate(attrs)
      |> Changeset.validate_required([:id, :title])

    data = Changeset.apply_changes(changeset)
    build_ticket(data, attrs)
  end

  @doc """
  Returns a changeset for creating a new ticket.
  Useful for validation before creation.
  """
  def create_changeset(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    {defaults(), @types_schema}
    |> Changeset.cast(attrs, Map.keys(@types_schema))
    |> cast_estimate(attrs)
    |> Changeset.validate_required([:id, :title])
  end

  @doc """
  Edits a ticket with the given changes.
  Uses changeset for casting and validation.

  ## Examples

      iex> ticket = Ticket.new(%{id: "1", title: "Original"})
      iex> Ticket.edit(ticket, %{title: "Updated"})
      %Ticket{id: "1", title: "Updated", ...}
  """
  def edit(%__MODULE__{} = ticket, changes) when is_map(changes) do
    changes = normalize_attrs(changes)
    changes = rename_points_to_estimate(changes)

    current_data = ticket_to_data(ticket)

    changeset =
      {current_data, @types_schema}
      |> Changeset.cast(changes, @edit_fields)
      |> validate_non_empty_title()
      |> validate_positive_estimate()

    updated_data = Changeset.apply_changes(changeset)
    data_to_ticket(updated_data, ticket)
  end

  @doc """
  Returns a changeset for editing a ticket.
  Useful for validation before applying changes.
  """
  def edit_changeset(%__MODULE__{} = ticket, changes) when is_map(changes) do
    changes = normalize_attrs(changes)
    changes = rename_points_to_estimate(changes)

    current_data = ticket_to_data(ticket)

    {current_data, @types_schema}
    |> Changeset.cast(changes, @edit_fields)
    |> validate_non_empty_title()
    |> validate_positive_estimate()
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

  defp defaults do
    %{
      id: nil,
      title: nil,
      description: nil,
      type: :feature,
      status: :pending,
      priority: :medium,
      estimate: nil,
      labels: [],
      acceptance_criteria: [],
      implementation_notes: nil
    }
  end

  defp normalize_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_binary(key) ->
        case safe_to_existing_atom(key) do
          {:ok, atom_key} -> Map.put(acc, atom_key, value)
          :error -> Map.put(acc, key, value)
        end

      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, value)
    end)
  end

  defp safe_to_existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  defp rename_points_to_estimate(attrs) do
    case Map.pop(attrs, :points) do
      {nil, attrs} -> attrs
      {points, attrs} -> Map.put(attrs, :estimate, points)
    end
  end

  defp cast_estimate(changeset, attrs) do
    estimate = Map.get(attrs, :estimate) || Map.get(attrs, "estimate")

    cond do
      is_nil(estimate) ->
        changeset

      is_integer(estimate) and estimate > 0 ->
        Changeset.put_change(changeset, :estimate, estimate)

      is_binary(estimate) ->
        case @estimate_mapping[String.downcase(estimate)] do
          nil -> changeset
          points -> Changeset.put_change(changeset, :estimate, points)
        end

      true ->
        changeset
    end
  end

  defp validate_non_empty_title(%Changeset{} = changeset) do
    case Changeset.get_change(changeset, :title) do
      "" -> %{changeset | changes: Map.delete(changeset.changes, :title)}
      _ -> changeset
    end
  end

  defp validate_positive_estimate(%Changeset{} = changeset) do
    case Changeset.get_change(changeset, :estimate) do
      nil -> changeset
      est when is_integer(est) and est > 0 -> changeset
      _ -> %{changeset | changes: Map.delete(changeset.changes, :estimate)}
    end
  end

  defp build_ticket(data, attrs) do
    now = DateTime.utc_now()

    %__MODULE__{
      id: data.id,
      title: data.title,
      description: data.description,
      type: data.type || :feature,
      status: data.status || :pending,
      priority: data.priority || :medium,
      estimate: data.estimate,
      labels: data.labels || [],
      acceptance_criteria: parse_acceptance_criteria(attrs),
      implementation_notes: data.implementation_notes,
      files: parse_files(Map.get(attrs, :files)),
      dependencies: parse_dependencies(Map.get(attrs, :dependencies)),
      external_refs: %{linear: nil, jira: nil, github: nil, asana: nil},
      timestamps: %{created_at: now, started_at: nil, completed_at: nil}
    }
  end

  defp ticket_to_data(%__MODULE__{} = ticket) do
    %{
      id: ticket.id,
      title: ticket.title,
      description: ticket.description,
      type: ticket.type,
      status: ticket.status,
      priority: ticket.priority,
      estimate: ticket.estimate,
      labels: ticket.labels,
      acceptance_criteria: ticket.acceptance_criteria,
      implementation_notes: ticket.implementation_notes
    }
  end

  defp data_to_ticket(data, original_ticket) do
    %__MODULE__{
      id: data.id,
      title: data.title,
      description: data.description,
      type: data.type,
      status: data.status,
      priority: data.priority,
      estimate: data.estimate,
      labels: data.labels,
      acceptance_criteria: original_ticket.acceptance_criteria,
      implementation_notes: data.implementation_notes,
      files: original_ticket.files,
      dependencies: original_ticket.dependencies,
      external_refs: original_ticket.external_refs,
      timestamps: original_ticket.timestamps
    }
  end

  defp parse_acceptance_criteria(attrs) do
    value = Map.get(attrs, :acceptance_criteria)
    List.wrap(value || [])
  end

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
