defmodule Albedo.Tickets do
  @moduledoc """
  Ticket management for Albedo sessions.
  Handles loading, saving, filtering, and status updates for tickets.
  """

  alias Albedo.Tickets.Ticket

  @tickets_file "tickets.json"
  @version "1.0"

  @type tickets_data :: %{
          version: String.t(),
          session_id: String.t(),
          project_name: String.t() | nil,
          task_description: String.t(),
          created_at: String.t(),
          updated_at: String.t(),
          summary: summary(),
          tickets: [Ticket.t()]
        }

  @type summary :: %{
          total: non_neg_integer(),
          pending: non_neg_integer(),
          in_progress: non_neg_integer(),
          completed: non_neg_integer(),
          total_points: non_neg_integer(),
          completed_points: non_neg_integer()
        }

  def load(session_dir) do
    path = Path.join(session_dir, @tickets_file)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, from_json(data)}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:file_read, reason}}
    end
  end

  def save(session_dir, tickets_data) do
    path = Path.join(session_dir, @tickets_file)
    updated_data = %{tickets_data | updated_at: DateTime.utc_now() |> DateTime.to_iso8601()}
    json = tickets_data_to_json(updated_data)

    case Jason.encode(json, pretty: true) do
      {:ok, content} ->
        File.write(path, content)

      {:error, reason} ->
        {:error, {:json_encode, reason}}
    end
  end

  def new(session_id, task, tickets, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    data = %{
      version: @version,
      session_id: session_id,
      project_name: Keyword.get(opts, :project_name),
      task_description: task,
      created_at: now,
      updated_at: now,
      summary: compute_summary(tickets),
      tickets: tickets
    }

    data
  end

  def list(tickets_data, opts \\ []) do
    tickets = tickets_data.tickets
    status_filter = Keyword.get(opts, :status)

    tickets =
      if status_filter do
        statuses = parse_status_filter(status_filter)
        Enum.filter(tickets, &(&1.status in statuses))
      else
        tickets
      end

    tickets
  end

  def get(tickets_data, id) do
    Enum.find(tickets_data.tickets, &(&1.id == to_string(id)))
  end

  def start(tickets_data, id) do
    update_ticket_status(tickets_data, id, :start)
  end

  def complete(tickets_data, id) do
    update_ticket_status(tickets_data, id, :complete)
  end

  def reset(tickets_data, id) do
    update_ticket_status(tickets_data, id, :reset)
  end

  def edit(tickets_data, id, changes) do
    id_str = to_string(id)

    case Enum.find_index(tickets_data.tickets, &(&1.id == id_str)) do
      nil ->
        {:error, :not_found}

      index ->
        ticket = Enum.at(tickets_data.tickets, index)
        updated_ticket = Ticket.edit(ticket, changes)
        updated_tickets = List.replace_at(tickets_data.tickets, index, updated_ticket)

        updated_data = %{
          tickets_data
          | tickets: updated_tickets,
            summary: compute_summary(updated_tickets)
        }

        {:ok, updated_data, updated_ticket}
    end
  end

  def add(tickets_data, attrs) do
    next_id = compute_next_id(tickets_data.tickets)
    ticket = Ticket.new(Map.put(attrs, :id, next_id))
    updated_tickets = tickets_data.tickets ++ [ticket]

    updated_data = %{
      tickets_data
      | tickets: updated_tickets,
        summary: compute_summary(updated_tickets)
    }

    {:ok, updated_data, ticket}
  end

  def delete(tickets_data, id) do
    id_str = to_string(id)

    case Enum.find_index(tickets_data.tickets, &(&1.id == id_str)) do
      nil ->
        {:error, :not_found}

      index ->
        deleted_ticket = Enum.at(tickets_data.tickets, index)
        updated_tickets = List.delete_at(tickets_data.tickets, index)

        updated_data = %{
          tickets_data
          | tickets: updated_tickets,
            summary: compute_summary(updated_tickets)
        }

        {:ok, updated_data, deleted_ticket}
    end
  end

  defp compute_next_id(tickets) do
    max_id =
      tickets
      |> Enum.map(fn t ->
        case Integer.parse(t.id) do
          {num, _} -> num
          :error -> 0
        end
      end)
      |> Enum.max(fn -> 0 end)

    to_string(max_id + 1)
  end

  def reset_all(tickets_data) do
    updated_tickets = Enum.map(tickets_data.tickets, &Ticket.reset/1)
    %{tickets_data | tickets: updated_tickets, summary: compute_summary(updated_tickets)}
  end

  def compute_summary(tickets) do
    total = length(tickets)
    pending = Enum.count(tickets, &(&1.status == :pending))
    in_progress = Enum.count(tickets, &(&1.status == :in_progress))
    completed = Enum.count(tickets, &(&1.status == :completed))
    total_points = tickets |> Enum.map(& &1.estimate) |> Enum.reject(&is_nil/1) |> Enum.sum()

    completed_points =
      tickets
      |> Enum.filter(&(&1.status == :completed))
      |> Enum.map(& &1.estimate)
      |> Enum.reject(&is_nil/1)
      |> Enum.sum()

    %{
      total: total,
      pending: pending,
      in_progress: in_progress,
      completed: completed,
      total_points: total_points,
      completed_points: completed_points
    }
  end

  defp update_ticket_status(tickets_data, id, action) do
    id_str = to_string(id)

    case Enum.find_index(tickets_data.tickets, &(&1.id == id_str)) do
      nil ->
        {:error, :not_found}

      index ->
        ticket = Enum.at(tickets_data.tickets, index)

        updated_ticket =
          case action do
            :start -> Ticket.start(ticket)
            :complete -> Ticket.complete(ticket)
            :reset -> Ticket.reset(ticket)
          end

        updated_tickets = List.replace_at(tickets_data.tickets, index, updated_ticket)

        updated_data = %{
          tickets_data
          | tickets: updated_tickets,
            summary: compute_summary(updated_tickets)
        }

        {:ok, updated_data, updated_ticket}
    end
  end

  defp parse_status_filter(status) when is_atom(status), do: [status]

  defp parse_status_filter(status) when is_binary(status) do
    status
    |> String.split(~r/[,\s]+/, trim: true)
    |> Enum.map(&String.to_existing_atom/1)
  end

  defp parse_status_filter(statuses) when is_list(statuses), do: statuses

  defp tickets_data_to_json(data) do
    %{
      "version" => data.version,
      "session_id" => data.session_id,
      "project_name" => data.project_name,
      "task_description" => data.task_description,
      "created_at" => data.created_at,
      "updated_at" => data.updated_at,
      "summary" => summary_to_json(data.summary),
      "tickets" => Enum.map(data.tickets, &Ticket.to_json/1)
    }
  end

  defp summary_to_json(summary) do
    %{
      "total" => summary.total,
      "pending" => summary.pending,
      "in_progress" => summary.in_progress,
      "completed" => summary.completed,
      "total_points" => summary.total_points,
      "completed_points" => summary.completed_points
    }
  end

  defp from_json(data) do
    %{
      version: data["version"] || @version,
      session_id: data["session_id"],
      project_name: data["project_name"],
      task_description: data["task_description"],
      created_at: data["created_at"],
      updated_at: data["updated_at"],
      summary: summary_from_json(data["summary"]),
      tickets: Enum.map(data["tickets"] || [], &Ticket.from_json/1)
    }
  end

  defp summary_from_json(nil),
    do: %{
      total: 0,
      pending: 0,
      in_progress: 0,
      completed: 0,
      total_points: 0,
      completed_points: 0
    }

  defp summary_from_json(summary) do
    %{
      total: summary["total"] || 0,
      pending: summary["pending"] || 0,
      in_progress: summary["in_progress"] || 0,
      completed: summary["completed"] || 0,
      total_points: summary["total_points"] || 0,
      completed_points: summary["completed_points"] || 0
    }
  end
end
