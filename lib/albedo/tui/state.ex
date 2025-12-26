defmodule Albedo.TUI.State do
  @moduledoc """
  State management for the TUI application.
  Uses Elm Architecture pattern: state + update.
  """

  alias Albedo.Tickets

  defstruct [
    :project_dir,
    :data,
    :projects,
    :projects_dir,
    :current_project,
    :selected_ticket,
    :active_panel,
    :panel_scroll,
    :detail_scroll,
    :terminal_size,
    :mode,
    :message,
    :quit,
    :edit_field,
    :edit_buffer,
    :edit_cursor,
    :edit_fields,
    :input_mode,
    :input_prompt,
    :input_buffer,
    :input_cursor,
    :confirm_action,
    :confirm_message
  ]

  @type panel :: :projects | :tickets | :detail
  @type mode :: :normal | :command | :confirm | :edit | :input

  @editable_fields [:title, :description, :type, :priority, :estimate, :labels]

  @type t :: %__MODULE__{
          project_dir: String.t() | nil,
          data: Tickets.Data.t() | nil,
          projects: [map()],
          current_project: non_neg_integer(),
          selected_ticket: non_neg_integer(),
          active_panel: panel(),
          panel_scroll: %{projects: non_neg_integer(), tickets: non_neg_integer()},
          terminal_size: {non_neg_integer(), non_neg_integer()},
          mode: mode(),
          message: String.t() | nil,
          quit: boolean(),
          edit_field: atom() | nil,
          edit_buffer: String.t() | nil,
          edit_cursor: non_neg_integer(),
          edit_fields: [atom()],
          input_mode: atom() | nil,
          input_prompt: String.t() | nil,
          input_buffer: String.t() | nil,
          input_cursor: non_neg_integer(),
          confirm_action: atom() | nil,
          confirm_message: String.t() | nil
        }

  def new(opts \\ []) do
    %__MODULE__{
      project_dir: opts[:project_dir],
      data: nil,
      projects: [],
      projects_dir: nil,
      current_project: 0,
      selected_ticket: 0,
      active_panel: :projects,
      panel_scroll: %{projects: 0, tickets: 0},
      detail_scroll: 0,
      terminal_size: {80, 24},
      mode: :normal,
      message: nil,
      quit: false,
      edit_field: nil,
      edit_buffer: nil,
      edit_cursor: 0,
      edit_fields: @editable_fields,
      input_mode: nil,
      input_prompt: nil,
      input_buffer: nil,
      input_cursor: 0,
      confirm_action: nil,
      confirm_message: nil
    }
  end

  def editable_fields, do: @editable_fields

  def load_projects(%__MODULE__{} = state, projects_dir) do
    projects =
      case File.ls(projects_dir) do
        {:ok, dirs} ->
          dirs
          |> Enum.reject(&String.starts_with?(&1, "."))
          |> Enum.filter(&has_project_file?(projects_dir, &1))
          |> Enum.sort(:desc)
          |> Enum.take(50)
          |> Enum.with_index()
          |> Enum.map(fn {dir, idx} ->
            load_project_info(projects_dir, dir, idx)
          end)

        {:error, _} ->
          []
      end

    %{state | projects: projects, projects_dir: projects_dir}
  end

  defp has_project_file?(projects_dir, dir) do
    project_file = Path.join([projects_dir, dir, "project.json"])
    legacy_file = Path.join([projects_dir, dir, "session.json"])
    File.exists?(project_file) or File.exists?(legacy_file)
  end

  defp load_project_info(projects_dir, id, index) do
    project_file = Path.join([projects_dir, id, "project.json"])
    legacy_file = Path.join([projects_dir, id, "session.json"])
    file_to_load = if File.exists?(project_file), do: project_file, else: legacy_file
    base = %{id: id, index: index, state: "unknown", task: ""}

    with true <- File.exists?(file_to_load),
         {:ok, content} <- File.read(file_to_load),
         {:ok, data} <- Jason.decode(content) do
      %{
        base
        | state: data["state"] || "unknown",
          task: String.slice(data["task"] || "", 0, 50)
      }
    else
      _ -> base
    end
  end

  def load_tickets(%__MODULE__{} = state, project_dir) do
    case Tickets.load(project_dir) do
      {:ok, data} ->
        {:ok, %{state | data: data, project_dir: project_dir, selected_ticket: 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def current_project(%__MODULE__{projects: projects, current_project: idx}) do
    Enum.at(projects, idx)
  end

  def current_ticket(%__MODULE__{data: nil}), do: nil

  def current_ticket(%__MODULE__{data: data, selected_ticket: idx}) do
    Enum.at(data.tickets, idx)
  end

  def visible_tickets(%__MODULE__{data: nil}), do: []

  def visible_tickets(%__MODULE__{data: data}) do
    data.tickets
    |> Enum.with_index()
  end

  def move_up(%__MODULE__{active_panel: :projects} = state) do
    new_idx = max(0, state.current_project - 1)
    %{state | current_project: new_idx}
  end

  def move_up(%__MODULE__{active_panel: :tickets, data: nil} = state), do: state

  def move_up(%__MODULE__{active_panel: :tickets} = state) do
    new_idx = max(0, state.selected_ticket - 1)
    %{state | selected_ticket: new_idx}
  end

  def move_up(%__MODULE__{active_panel: :detail} = state) do
    new_scroll = max(0, state.detail_scroll - 1)
    %{state | detail_scroll: new_scroll}
  end

  def move_down(%__MODULE__{active_panel: :projects, projects: projects} = state) do
    max_idx = max(0, length(projects) - 1)
    new_idx = min(max_idx, state.current_project + 1)
    %{state | current_project: new_idx}
  end

  def move_down(%__MODULE__{active_panel: :tickets, data: nil} = state), do: state

  def move_down(%__MODULE__{active_panel: :tickets, data: data} = state) do
    max_idx = max(0, length(data.tickets) - 1)
    new_idx = min(max_idx, state.selected_ticket + 1)
    %{state | selected_ticket: new_idx}
  end

  def move_down(%__MODULE__{active_panel: :detail} = state) do
    %{state | detail_scroll: state.detail_scroll + 1}
  end

  def next_panel(%__MODULE__{active_panel: :projects} = state) do
    %{state | active_panel: :tickets}
  end

  def next_panel(%__MODULE__{active_panel: :tickets} = state) do
    %{state | active_panel: :detail}
  end

  def next_panel(%__MODULE__{active_panel: :detail} = state) do
    %{state | active_panel: :projects}
  end

  def prev_panel(%__MODULE__{active_panel: :projects} = state) do
    %{state | active_panel: :detail}
  end

  def prev_panel(%__MODULE__{active_panel: :tickets} = state) do
    %{state | active_panel: :projects}
  end

  def prev_panel(%__MODULE__{active_panel: :detail} = state) do
    %{state | active_panel: :tickets}
  end

  def scroll_detail_up(%__MODULE__{} = state) do
    new_scroll = max(0, state.detail_scroll - 1)
    %{state | detail_scroll: new_scroll}
  end

  def scroll_detail_down(%__MODULE__{} = state) do
    %{state | detail_scroll: state.detail_scroll + 1}
  end

  def reset_detail_scroll(%__MODULE__{} = state) do
    %{state | detail_scroll: 0}
  end

  def set_message(%__MODULE__{} = state, message) do
    %{state | message: message}
  end

  def clear_message(%__MODULE__{} = state) do
    %{state | message: nil}
  end

  def quit(%__MODULE__{} = state) do
    %{state | quit: true}
  end

  def enter_edit_mode(%__MODULE__{} = state) do
    case current_ticket(state) do
      nil ->
        state

      ticket ->
        %{
          state
          | mode: :edit,
            edit_field: :title,
            edit_buffer: ticket.title,
            edit_cursor: String.length(ticket.title)
        }
    end
  end

  def exit_edit_mode(%__MODULE__{} = state) do
    %{
      state
      | mode: :normal,
        edit_field: nil,
        edit_buffer: nil,
        edit_cursor: 0
    }
  end

  def next_edit_field(%__MODULE__{edit_field: current} = state) do
    fields = @editable_fields
    current_idx = Enum.find_index(fields, &(&1 == current)) || 0
    next_idx = rem(current_idx + 1, length(fields))
    next_field = Enum.at(fields, next_idx)

    ticket = current_ticket(state)
    value = get_field_value(ticket, next_field)

    %{
      state
      | edit_field: next_field,
        edit_buffer: value,
        edit_cursor: String.length(value)
    }
  end

  def prev_edit_field(%__MODULE__{edit_field: current} = state) do
    fields = @editable_fields
    current_idx = Enum.find_index(fields, &(&1 == current)) || 0
    prev_idx = if current_idx == 0, do: length(fields) - 1, else: current_idx - 1
    prev_field = Enum.at(fields, prev_idx)

    ticket = current_ticket(state)
    value = get_field_value(ticket, prev_field)

    %{
      state
      | edit_field: prev_field,
        edit_buffer: value,
        edit_cursor: String.length(value)
    }
  end

  def edit_insert_char(%__MODULE__{edit_buffer: buffer, edit_cursor: cursor} = state, char) do
    {before, after_cursor} = String.split_at(buffer, cursor)
    new_buffer = before <> char <> after_cursor

    %{state | edit_buffer: new_buffer, edit_cursor: cursor + String.length(char)}
  end

  def edit_delete_char(%__MODULE__{edit_buffer: buffer, edit_cursor: cursor} = state) do
    if cursor > 0 do
      {before, after_cursor} = String.split_at(buffer, cursor)
      new_before = String.slice(before, 0, String.length(before) - 1)
      new_buffer = new_before <> after_cursor

      %{state | edit_buffer: new_buffer, edit_cursor: cursor - 1}
    else
      state
    end
  end

  def edit_move_cursor_left(%__MODULE__{edit_cursor: cursor} = state) do
    %{state | edit_cursor: max(0, cursor - 1)}
  end

  def edit_move_cursor_right(%__MODULE__{edit_buffer: buffer, edit_cursor: cursor} = state) do
    %{state | edit_cursor: min(String.length(buffer), cursor + 1)}
  end

  def edit_cursor_home(%__MODULE__{} = state) do
    %{state | edit_cursor: 0}
  end

  def edit_cursor_end(%__MODULE__{edit_buffer: buffer} = state) do
    %{state | edit_cursor: String.length(buffer)}
  end

  def get_edit_changes(%__MODULE__{edit_field: field, edit_buffer: buffer}) do
    %{field => parse_field_value(field, buffer)}
  end

  defp get_field_value(ticket, :title), do: ticket.title || ""
  defp get_field_value(ticket, :description), do: ticket.description || ""
  defp get_field_value(ticket, :type), do: to_string(ticket.type)
  defp get_field_value(ticket, :priority), do: to_string(ticket.priority)

  defp get_field_value(ticket, :estimate),
    do: if(ticket.estimate, do: to_string(ticket.estimate), else: "")

  defp get_field_value(ticket, :labels), do: Enum.join(ticket.labels, ", ")
  defp get_field_value(_, _), do: ""

  defp parse_field_value(:labels, value), do: String.split(value, ~r/,\s*/, trim: true)
  defp parse_field_value(:estimate, ""), do: nil

  defp parse_field_value(:estimate, value) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_field_value(:type, value) do
    case value do
      "feature" -> :feature
      "enhancement" -> :enhancement
      "bugfix" -> :bugfix
      "chore" -> :chore
      "docs" -> :docs
      "test" -> :test
      _ -> :feature
    end
  end

  defp parse_field_value(:priority, value) do
    case value do
      "urgent" -> :urgent
      "high" -> :high
      "medium" -> :medium
      "low" -> :low
      "none" -> :none
      _ -> :medium
    end
  end

  defp parse_field_value(_, value), do: value

  def enter_input_mode(%__MODULE__{} = state, input_mode, prompt) do
    %{
      state
      | mode: :input,
        input_mode: input_mode,
        input_prompt: prompt,
        input_buffer: "",
        input_cursor: 0
    }
  end

  def exit_input_mode(%__MODULE__{} = state) do
    %{
      state
      | mode: :normal,
        input_mode: nil,
        input_prompt: nil,
        input_buffer: nil,
        input_cursor: 0
    }
  end

  def input_insert_char(%__MODULE__{input_buffer: buffer, input_cursor: cursor} = state, char) do
    {before, after_cursor} = String.split_at(buffer, cursor)
    new_buffer = before <> char <> after_cursor
    %{state | input_buffer: new_buffer, input_cursor: cursor + String.length(char)}
  end

  def input_delete_char(%__MODULE__{input_buffer: buffer, input_cursor: cursor} = state) do
    if cursor > 0 do
      {before, after_cursor} = String.split_at(buffer, cursor)
      new_before = String.slice(before, 0, String.length(before) - 1)
      new_buffer = new_before <> after_cursor
      %{state | input_buffer: new_buffer, input_cursor: cursor - 1}
    else
      state
    end
  end

  def input_move_cursor_left(%__MODULE__{input_cursor: cursor} = state) do
    %{state | input_cursor: max(0, cursor - 1)}
  end

  def input_move_cursor_right(%__MODULE__{input_buffer: buffer, input_cursor: cursor} = state) do
    %{state | input_cursor: min(String.length(buffer), cursor + 1)}
  end

  def enter_confirm_mode(%__MODULE__{} = state, action, message) do
    %{
      state
      | mode: :confirm,
        confirm_action: action,
        confirm_message: message
    }
  end

  def exit_confirm_mode(%__MODULE__{} = state) do
    %{
      state
      | mode: :normal,
        confirm_action: nil,
        confirm_message: nil
    }
  end

  def delete_project(%__MODULE__{projects: projects, current_project: idx} = state) do
    updated_projects = List.delete_at(projects, idx)
    new_idx = min(idx, max(0, length(updated_projects) - 1))
    %{state | projects: updated_projects, current_project: new_idx}
  end

  def update_project_task(%__MODULE__{projects: projects, current_project: idx} = state, new_task) do
    updated_projects =
      List.update_at(projects, idx, fn project ->
        %{project | task: String.slice(new_task, 0, 50)}
      end)

    %{state | projects: updated_projects}
  end
end
