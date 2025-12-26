defmodule Albedo.Tickets.Exporter do
  @moduledoc """
  Behavior and dispatcher for ticket exporters.
  Supports multiple export formats for external system compatibility.
  """

  alias Albedo.Tickets.Exporters

  @type format :: :json | :csv | :markdown | :github
  @type export_result :: {:ok, String.t()} | {:error, term()}

  @callback export(tickets_data :: map(), opts :: keyword()) :: export_result()
  @callback file_extension() :: String.t()
  @callback format_name() :: String.t()

  @formats %{
    json: Exporters.JSON,
    csv: Exporters.CSV,
    markdown: Exporters.Markdown,
    github: Exporters.GitHub
  }

  def formats, do: Map.keys(@formats)

  def export(tickets_data, format, opts \\ []) when is_atom(format) do
    case @formats[format] do
      nil -> {:error, {:unknown_format, format}}
      module -> module.export(tickets_data, opts)
    end
  end

  def export_to_file(tickets_data, format, output_path, opts \\ []) do
    case export(tickets_data, format, opts) do
      {:ok, content} ->
        File.write(output_path, content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def file_extension(format) do
    case @formats[format] do
      nil -> ".txt"
      module -> module.file_extension()
    end
  end

  def format_name(format) do
    case @formats[format] do
      nil -> to_string(format)
      module -> module.format_name()
    end
  end

  def default_filename(project_id, format) do
    ext = file_extension(format)
    "#{project_id}_tickets#{ext}"
  end

  def filter_by_status(tickets, opts) do
    case Keyword.get(opts, :status) do
      nil -> tickets
      status -> Enum.filter(tickets, &(&1.status == status))
    end
  end
end
