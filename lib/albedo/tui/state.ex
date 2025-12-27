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
    :viewed_ticket,
    :selected_file,
    :viewed_file,
    :research_files,
    :active_panel,
    :detail_content,
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
    :confirm_message,
    :wizard_data,
    :modal,
    :modal_data,
    :modal_scroll,
    :modal_task_ref
  ]

  @type panel :: :projects | :tickets | :research | :detail
  @type mode :: :normal | :command | :confirm | :edit | :input | :help | :modal

  @editable_fields [:title, :description, :type, :priority, :estimate, :labels]

  @type research_file :: %{
          name: String.t(),
          path: String.t(),
          type: :markdown | :json
        }

  @type modal_data :: %{
          type: :plan | :analyze,
          phase: :input | :running | :completed | :failed,
          name: String.t(),
          task: String.t(),
          name_buffer: String.t(),
          task_buffer: String.t(),
          active_field: :name | :title | :task,
          cursor: non_neg_integer(),
          logs: [String.t()],
          result: map() | nil,
          current_agent: non_neg_integer(),
          total_agents: non_neg_integer(),
          agent_name: String.t() | nil
        }

  @type t :: %__MODULE__{
          project_dir: String.t() | nil,
          data: Tickets.tickets_data() | nil,
          projects: [map()],
          current_project: non_neg_integer(),
          selected_ticket: non_neg_integer() | nil,
          viewed_ticket: non_neg_integer() | nil,
          selected_file: non_neg_integer() | nil,
          viewed_file: non_neg_integer() | nil,
          research_files: [research_file()],
          active_panel: panel(),
          detail_content: :ticket | :research,
          panel_scroll: %{
            projects: non_neg_integer(),
            tickets: non_neg_integer(),
            research: non_neg_integer()
          },
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
          confirm_message: String.t() | nil,
          wizard_data: map() | nil,
          modal: :plan | :analyze | nil,
          modal_data: modal_data() | nil,
          modal_scroll: non_neg_integer(),
          modal_task_ref: reference() | nil
        }

  def new(opts \\ []) do
    %__MODULE__{
      project_dir: opts[:project_dir],
      data: nil,
      projects: [],
      projects_dir: nil,
      current_project: 0,
      selected_ticket: nil,
      viewed_ticket: nil,
      selected_file: nil,
      viewed_file: nil,
      research_files: [],
      active_panel: :projects,
      detail_content: :ticket,
      panel_scroll: %{projects: 0, tickets: 0, research: 0},
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
      confirm_message: nil,
      wizard_data: nil,
      modal: nil,
      modal_data: nil,
      modal_scroll: 0,
      modal_task_ref: nil
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
    File.exists?(project_file)
  end

  defp load_project_info(projects_dir, id, index) do
    project_file = Path.join([projects_dir, id, "project.json"])
    base = %{id: id, index: index, state: "unknown", task: ""}

    with true <- File.exists?(project_file),
         {:ok, content} <- File.read(project_file),
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
        files = load_research_files(project_dir)

        {:ok,
         %{
           state
           | data: data,
             project_dir: project_dir,
             selected_ticket: nil,
             viewed_ticket: nil,
             selected_file: nil,
             viewed_file: nil,
             research_files: files,
             detail_scroll: 0
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_research_files(project_dir) do
    case File.ls(project_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&research_file?/1)
        |> Enum.sort()
        |> Enum.map(fn file ->
          %{
            name: file,
            path: Path.join(project_dir, file),
            type: file_type(file)
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp research_file?(name) do
    ext = Path.extname(name)
    ext in [".md", ".json"]
  end

  defp file_type(name) do
    case Path.extname(name) do
      ".md" -> :markdown
      ".json" -> :json
      _ -> :unknown
    end
  end

  def current_project(%__MODULE__{projects: projects, current_project: idx}) do
    Enum.at(projects, idx)
  end

  def current_ticket(%__MODULE__{data: nil}), do: nil
  def current_ticket(%__MODULE__{selected_ticket: nil}), do: nil

  def current_ticket(%__MODULE__{data: data, selected_ticket: idx}) do
    Enum.at(data.tickets, idx)
  end

  def current_research_file(%__MODULE__{research_files: []}), do: nil
  def current_research_file(%__MODULE__{selected_file: nil}), do: nil

  def current_research_file(%__MODULE__{research_files: files, selected_file: idx}) do
    Enum.at(files, idx)
  end

  def view_current_ticket(%__MODULE__{selected_ticket: nil} = state), do: state

  def view_current_ticket(%__MODULE__{selected_ticket: idx} = state) do
    %{state | viewed_ticket: idx, detail_content: :ticket, detail_scroll: 0}
  end

  def view_current_file(%__MODULE__{selected_file: nil} = state), do: state

  def view_current_file(%__MODULE__{selected_file: idx} = state) do
    %{state | viewed_file: idx, detail_content: :research, detail_scroll: 0}
  end

  def move_up(%__MODULE__{active_panel: :projects} = state) do
    new_idx = max(0, state.current_project - 1)
    %{state | current_project: new_idx}
  end

  def move_up(%__MODULE__{active_panel: :tickets, data: nil} = state), do: state

  def move_up(%__MODULE__{active_panel: :tickets, selected_ticket: nil, data: data} = state) do
    if data.tickets != [], do: %{state | selected_ticket: 0}, else: state
  end

  def move_up(%__MODULE__{active_panel: :tickets} = state) do
    new_idx = max(0, state.selected_ticket - 1)
    %{state | selected_ticket: new_idx}
  end

  def move_up(%__MODULE__{active_panel: :research, research_files: []} = state), do: state
  def move_up(%__MODULE__{active_panel: :research, selected_file: nil} = state), do: state

  def move_up(%__MODULE__{active_panel: :research} = state) do
    new_idx = max(0, state.selected_file - 1)
    %{state | selected_file: new_idx, detail_scroll: 0}
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

  def move_down(%__MODULE__{active_panel: :tickets, selected_ticket: nil, data: data} = state) do
    if data.tickets != [], do: %{state | selected_ticket: 0}, else: state
  end

  def move_down(%__MODULE__{active_panel: :tickets, data: data} = state) do
    max_idx = max(0, length(data.tickets) - 1)
    new_idx = min(max_idx, state.selected_ticket + 1)
    %{state | selected_ticket: new_idx}
  end

  def move_down(%__MODULE__{active_panel: :research, research_files: []} = state), do: state

  def move_down(
        %__MODULE__{active_panel: :research, selected_file: nil, research_files: files} = state
      ) do
    if files != [], do: %{state | selected_file: 0, detail_scroll: 0}, else: state
  end

  def move_down(%__MODULE__{active_panel: :research, research_files: files} = state) do
    max_idx = max(0, length(files) - 1)
    new_idx = min(max_idx, state.selected_file + 1)
    %{state | selected_file: new_idx, detail_scroll: 0}
  end

  def move_down(%__MODULE__{active_panel: :detail} = state) do
    %{state | detail_scroll: state.detail_scroll + 1}
  end

  def next_panel(%__MODULE__{active_panel: :projects} = state) do
    state
    |> sync_project_selection()
    |> Map.put(:active_panel, :tickets)
    |> maybe_select_first_ticket()
  end

  def next_panel(%__MODULE__{active_panel: :tickets} = state) do
    state
    |> sync_ticket_selection()
    |> Map.put(:active_panel, :research)
    |> maybe_select_first_file()
  end

  def next_panel(%__MODULE__{active_panel: :research} = state) do
    state
    |> sync_file_selection()
    |> Map.put(:active_panel, :detail)
  end

  def next_panel(%__MODULE__{active_panel: :detail} = state) do
    %{state | active_panel: :projects}
    |> sync_project_selection()
  end

  def prev_panel(%__MODULE__{active_panel: :projects} = state) do
    state
    |> sync_project_selection()
    |> Map.put(:active_panel, :detail)
  end

  def prev_panel(%__MODULE__{active_panel: :tickets} = state) do
    state
    |> sync_ticket_selection()
    |> Map.put(:active_panel, :projects)
    |> sync_project_selection()
  end

  def prev_panel(%__MODULE__{active_panel: :research} = state) do
    state
    |> sync_file_selection()
    |> Map.put(:active_panel, :tickets)
    |> maybe_select_first_ticket()
  end

  def prev_panel(%__MODULE__{active_panel: :detail} = state) do
    %{state | active_panel: :research}
    |> maybe_select_first_file()
  end

  @doc """
  Set active panel with auto-selection of first item if needed.
  Syncs selection when leaving a panel.
  """
  def set_active_panel(%__MODULE__{active_panel: from} = state, to) do
    state
    |> sync_selection_on_leave(from)
    |> Map.put(:active_panel, to)
    |> auto_select_on_enter(to)
  end

  defp sync_selection_on_leave(state, :projects), do: sync_project_selection(state)
  defp sync_selection_on_leave(state, :tickets), do: sync_ticket_selection(state)
  defp sync_selection_on_leave(state, :research), do: sync_file_selection(state)
  defp sync_selection_on_leave(state, _), do: state

  defp auto_select_on_enter(state, :projects), do: sync_project_selection(state)
  defp auto_select_on_enter(state, :tickets), do: maybe_select_first_ticket(state)
  defp auto_select_on_enter(state, :research), do: maybe_select_first_file(state)
  defp auto_select_on_enter(state, _), do: state

  defp sync_project_selection(%{project_dir: nil} = state), do: state

  defp sync_project_selection(%{project_dir: project_dir, projects: projects} = state) do
    loaded_id = Path.basename(project_dir)

    case Enum.find_index(projects, &(&1.id == loaded_id)) do
      nil -> state
      index -> %{state | current_project: index}
    end
  end

  defp sync_ticket_selection(%{viewed_ticket: nil, data: %{tickets: [_ | _]}} = state) do
    %{state | selected_ticket: 0}
  end

  defp sync_ticket_selection(%{viewed_ticket: nil} = state), do: state

  defp sync_ticket_selection(%{viewed_ticket: idx} = state) do
    %{state | selected_ticket: idx}
  end

  defp sync_file_selection(%{viewed_file: nil, research_files: [_ | _]} = state) do
    %{state | selected_file: 0}
  end

  defp sync_file_selection(%{viewed_file: nil} = state), do: state

  defp sync_file_selection(%{viewed_file: idx} = state) do
    %{state | selected_file: idx}
  end

  defp maybe_select_first_ticket(%{selected_ticket: nil, data: %{tickets: [_ | _]}} = state) do
    %{state | selected_ticket: 0}
  end

  defp maybe_select_first_ticket(state), do: state

  defp maybe_select_first_file(%{selected_file: nil, research_files: [_ | _]} = state) do
    %{state | selected_file: 0}
  end

  defp maybe_select_first_file(state), do: state

  def reset_detail_scroll(%__MODULE__{} = state) do
    %{state | detail_scroll: 0}
  end

  def set_message(%__MODULE__{} = state, message) do
    %{state | message: message}
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
        input_cursor: 0,
        wizard_data: nil
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

  def enter_help_mode(%__MODULE__{} = state) do
    %{state | mode: :help}
  end

  def exit_help_mode(%__MODULE__{} = state) do
    %{state | mode: :normal}
  end

  def enter_modal(%__MODULE__{} = state, type) do
    default_path = if type == :analyze, do: File.cwd!(), else: ""

    modal_data = %{
      type: type,
      phase: :input,
      name: "",
      task: "",
      name_buffer: default_path,
      title_buffer: "",
      task_buffer: "",
      active_field: :name,
      cursor: String.length(default_path),
      logs: [],
      result: nil,
      current_agent: 0,
      total_agents: 0,
      agent_name: nil
    }

    %{
      state
      | mode: :modal,
        modal: type,
        modal_data: modal_data,
        modal_scroll: 0,
        modal_task_ref: nil
    }
  end

  def start_modal_operation(%__MODULE__{modal_data: data} = state) do
    updated_data = %{
      data
      | phase: :running,
        name: data.name_buffer,
        task: data.task_buffer,
        logs: ["Starting #{data.type}..."]
    }

    %{state | modal_data: updated_data}
  end

  def add_modal_log(%__MODULE__{modal_data: nil} = state, _log), do: state

  def add_modal_log(%__MODULE__{modal_data: data} = state, log) do
    updated_data = %{data | logs: data.logs ++ [log]}
    %{state | modal_data: updated_data}
  end

  def update_agent_progress(%__MODULE__{modal_data: nil} = state, _current, _total, _name),
    do: state

  def update_agent_progress(%__MODULE__{modal_data: data} = state, current, total, name) do
    updated_data = %{data | current_agent: current, total_agents: total, agent_name: name}
    %{state | modal_data: updated_data}
  end

  def complete_modal(%__MODULE__{modal_data: nil} = state, _status, _result), do: state

  def complete_modal(%__MODULE__{modal_data: data} = state, status, result) do
    updated_data = %{data | phase: status, result: result}
    %{state | modal_data: updated_data}
  end

  def modal_insert_char(%__MODULE__{modal_data: data} = state, char) do
    {buffer_key, buffer} = get_active_modal_buffer(data)
    cursor = data.cursor
    {before, after_cursor} = String.split_at(buffer, cursor)
    new_buffer = before <> char <> after_cursor
    updated_data = Map.put(data, buffer_key, new_buffer) |> Map.put(:cursor, cursor + 1)
    %{state | modal_data: updated_data}
  end

  def modal_delete_char(%__MODULE__{modal_data: %{cursor: 0}} = state), do: state

  def modal_delete_char(%__MODULE__{modal_data: data} = state) do
    {buffer_key, buffer} = get_active_modal_buffer(data)
    cursor = data.cursor
    {before, after_cursor} = String.split_at(buffer, cursor)
    new_before = String.slice(before, 0, String.length(before) - 1)
    new_buffer = new_before <> after_cursor
    updated_data = Map.put(data, buffer_key, new_buffer) |> Map.put(:cursor, cursor - 1)
    %{state | modal_data: updated_data}
  end

  def modal_move_cursor_left(%__MODULE__{modal_data: data} = state) do
    updated_data = %{data | cursor: max(0, data.cursor - 1)}
    %{state | modal_data: updated_data}
  end

  def modal_move_cursor_right(%__MODULE__{modal_data: data} = state) do
    {_buffer_key, buffer} = get_active_modal_buffer(data)
    updated_data = %{data | cursor: min(String.length(buffer), data.cursor + 1)}
    %{state | modal_data: updated_data}
  end

  def modal_next_field(
        %__MODULE__{modal: :analyze, modal_data: %{active_field: :name} = data} = state
      ) do
    updated_data = %{data | active_field: :title, cursor: String.length(data.title_buffer)}
    %{state | modal_data: updated_data}
  end

  def modal_next_field(
        %__MODULE__{modal: :analyze, modal_data: %{active_field: :title} = data} = state
      ) do
    updated_data = %{data | active_field: :task, cursor: String.length(data.task_buffer)}
    %{state | modal_data: updated_data}
  end

  def modal_next_field(
        %__MODULE__{modal: :analyze, modal_data: %{active_field: :task} = data} = state
      ) do
    updated_data = %{data | active_field: :name, cursor: String.length(data.name_buffer)}
    %{state | modal_data: updated_data}
  end

  def modal_next_field(%__MODULE__{modal_data: %{active_field: :name} = data} = state) do
    updated_data = %{data | active_field: :task, cursor: String.length(data.task_buffer)}
    %{state | modal_data: updated_data}
  end

  def modal_next_field(%__MODULE__{modal_data: %{active_field: :task} = data} = state) do
    updated_data = %{data | active_field: :name, cursor: String.length(data.name_buffer)}
    %{state | modal_data: updated_data}
  end

  def modal_prev_field(%__MODULE__{modal_data: data} = state) do
    modal_next_field(%{state | modal_data: data})
  end

  defp get_active_modal_buffer(%{active_field: :name, name_buffer: buffer}),
    do: {:name_buffer, buffer}

  defp get_active_modal_buffer(%{active_field: :title, title_buffer: buffer}),
    do: {:title_buffer, buffer}

  defp get_active_modal_buffer(%{active_field: :task, task_buffer: buffer}),
    do: {:task_buffer, buffer}

  def exit_modal(%__MODULE__{} = state) do
    %{
      state
      | mode: :normal,
        modal: nil,
        modal_data: nil,
        modal_scroll: 0,
        modal_task_ref: nil
    }
  end

  def scroll_modal_up(%__MODULE__{modal_scroll: scroll} = state) do
    %{state | modal_scroll: max(0, scroll - 1)}
  end

  def scroll_modal_down(%__MODULE__{modal_data: nil} = state), do: state

  def scroll_modal_down(%__MODULE__{modal_scroll: scroll, modal_data: data} = state) do
    max_scroll = max(0, length(data.logs) - 1)
    %{state | modal_scroll: min(max_scroll, scroll + 1)}
  end
end
