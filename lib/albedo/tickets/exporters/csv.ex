defmodule Albedo.Tickets.Exporters.CSV do
  @moduledoc """
  Exports tickets to CSV format.
  Universal format compatible with spreadsheets and most tools.
  """

  @behaviour Albedo.Tickets.Exporter

  alias Albedo.Tickets.Exporter

  @headers [
    "id",
    "title",
    "type",
    "status",
    "priority",
    "estimate",
    "labels",
    "description",
    "files_create",
    "files_modify",
    "blocked_by",
    "blocks"
  ]

  @impl true
  def export(tickets_data, opts \\ []) do
    tickets = Exporter.filter_by_status(tickets_data.tickets, opts)

    rows = [
      @headers | Enum.map(tickets, &ticket_to_row/1)
    ]

    csv = Enum.map_join(rows, "\n", &format_row/1)

    {:ok, csv}
  end

  @impl true
  def file_extension, do: ".csv"

  @impl true
  def format_name, do: "CSV"

  defp ticket_to_row(ticket) do
    [
      ticket.id,
      ticket.title,
      to_string(ticket.type),
      to_string(ticket.status),
      to_string(ticket.priority),
      if(ticket.estimate, do: to_string(ticket.estimate), else: ""),
      Enum.join(ticket.labels, ";"),
      ticket.description || "",
      Enum.join(ticket.files.create, ";"),
      Enum.join(ticket.files.modify, ";"),
      Enum.join(ticket.dependencies.blocked_by, ";"),
      Enum.join(ticket.dependencies.blocks, ";")
    ]
  end

  defp format_row(row) do
    Enum.map_join(row, ",", &escape_csv_field/1)
  end

  defp escape_csv_field(nil), do: ""

  defp escape_csv_field(field) when is_binary(field) do
    if String.contains?(field, [",", "\"", "\n", "\r"]) do
      "\"#{String.replace(field, "\"", "\"\"")}\""
    else
      field
    end
  end

  defp escape_csv_field(field), do: to_string(field)
end
