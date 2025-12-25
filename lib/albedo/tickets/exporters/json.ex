defmodule Albedo.Tickets.Exporters.JSON do
  @moduledoc """
  Exports tickets to JSON format.
  Default export format, suitable for programmatic consumption.
  """

  @behaviour Albedo.Tickets.Exporter

  alias Albedo.Tickets.Exporter
  alias Albedo.Tickets.Ticket

  @impl true
  def export(tickets_data, opts \\ []) do
    tickets = Exporter.filter_by_status(tickets_data.tickets, opts)

    output = %{
      "version" => tickets_data.version,
      "session_id" => tickets_data.session_id,
      "project_name" => tickets_data.project_name,
      "task_description" => tickets_data.task_description,
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "summary" => format_summary(tickets),
      "tickets" => Enum.map(tickets, &Ticket.to_json/1)
    }

    case Jason.encode(output, pretty: true) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_encode, reason}}
    end
  end

  @impl true
  def file_extension, do: ".json"

  @impl true
  def format_name, do: "JSON"

  defp format_summary(tickets) do
    %{
      "total" => length(tickets),
      "pending" => Enum.count(tickets, &(&1.status == :pending)),
      "in_progress" => Enum.count(tickets, &(&1.status == :in_progress)),
      "completed" => Enum.count(tickets, &(&1.status == :completed)),
      "total_points" => tickets |> Enum.map(& &1.estimate) |> Enum.reject(&is_nil/1) |> Enum.sum()
    }
  end
end
