defmodule Albedo.TUI.State do
  @moduledoc """
  State management for the TUI application.
  Uses Elm Architecture pattern: state + update.

  Delegates to focused sub-modules:
  - State.Modal - Modal dialog operations
  - State.Editing - Edit mode, input mode, confirm mode
  """

  alias Albedo.Tickets
  alias Albedo.TUI.State.{Editing, Modal}
  alias Albedo.Utils.Helpers

  require Logger

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
    :input_mode,
    :input_prompt,
    :input_buffer,
    :input_cursor,
    :confirm_action,
    :confirm_message,
    :modal,
    :modal_data,
    :modal_scroll,
    :modal_task_ref
  ]

  @type panel :: :projects | :tickets | :research | :detail
  @type mode :: :normal | :command | :confirm | :edit | :input | :help | :modal

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
          input_mode: atom() | nil,
          input_prompt: String.t() | nil,
          input_buffer: String.t() | nil,
          input_cursor: non_neg_integer(),
          confirm_action: atom() | nil,
          confirm_message: String.t() | nil,
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
      input_mode: nil,
      input_prompt: nil,
      input_buffer: nil,
      input_cursor: 0,
      confirm_action: nil,
      confirm_message: nil,
      modal: nil,
      modal_data: nil,
      modal_scroll: 0,
      modal_task_ref: nil
    }
  end

  defdelegate editable_fields, to: Editing

  def load_projects(%__MODULE__{} = state, projects_dir) do
    projects =
      case File.ls(projects_dir) do
        {:ok, dirs} ->
          dirs
          |> Enum.reject(&String.starts_with?(&1, "."))
          |> Enum.filter(&has_project_file?(projects_dir, &1))
          |> Enum.map(&load_project_info(projects_dir, &1))
          |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
          |> Enum.take(50)
          |> Enum.with_index()
          |> Enum.map(fn {project, idx} -> %{project | index: idx} end)

        {:error, reason} ->
          Logger.warning("Failed to list projects directory: #{inspect(reason)}")
          []
      end

    %{state | projects: projects, projects_dir: projects_dir}
  end

  defp has_project_file?(projects_dir, dir) do
    if Helpers.safe_path_component?(dir) do
      project_file = Path.join([projects_dir, dir, "project.json"])
      File.exists?(project_file)
    else
      Logger.warning("Skipping invalid project directory: #{inspect(dir)}")
      false
    end
  end

  defp load_project_info(projects_dir, id) do
    project_file = Path.join([projects_dir, id, "project.json"])
    fallback_time = DateTime.from_unix!(0)
    base = %{id: id, index: 0, state: "unknown", task: "", created_at: fallback_time}

    with true <- File.exists?(project_file),
         {:ok, content} <- File.read(project_file),
         {:ok, data} <- Jason.decode(content) do
      created_at = parse_project_datetime(data["created_at"]) || fallback_time

      %{
        base
        | state: data["state"] || "unknown",
          task: String.slice(data["task"] || "", 0, 50),
          created_at: created_at
      }
    else
      _ -> base
    end
  end

  defp parse_project_datetime(nil), do: nil

  defp parse_project_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
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

  def load_project_without_tickets(%__MODULE__{} = state, project_dir) do
    files = load_research_files(project_dir)
    project_id = Path.basename(project_dir)
    project = Enum.find(state.projects, &(&1.id == project_id))
    task = if project, do: project.task, else: ""
    empty_data = Tickets.new(project_id, task, [])

    %{
      state
      | data: empty_data,
        project_dir: project_dir,
        selected_ticket: nil,
        viewed_ticket: nil,
        selected_file: nil,
        viewed_file: nil,
        research_files: files,
        detail_scroll: 0
    }
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

      {:error, reason} ->
        Logger.debug("Failed to list research files in #{project_dir}: #{inspect(reason)}")
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
    |> adjust_panel_scroll(:projects, new_idx)
  end

  def move_up(%__MODULE__{active_panel: :tickets, data: nil} = state), do: state

  def move_up(%__MODULE__{active_panel: :tickets, selected_ticket: nil, data: data} = state) do
    if data.tickets != [], do: %{state | selected_ticket: 0}, else: state
  end

  def move_up(%__MODULE__{active_panel: :tickets} = state) do
    new_idx = max(0, state.selected_ticket - 1)

    %{state | selected_ticket: new_idx}
    |> adjust_panel_scroll(:tickets, new_idx)
  end

  def move_up(%__MODULE__{active_panel: :research, research_files: []} = state), do: state
  def move_up(%__MODULE__{active_panel: :research, selected_file: nil} = state), do: state

  def move_up(%__MODULE__{active_panel: :research} = state) do
    new_idx = max(0, state.selected_file - 1)

    %{state | selected_file: new_idx, detail_scroll: 0}
    |> adjust_panel_scroll(:research, new_idx)
  end

  def move_up(%__MODULE__{active_panel: :detail} = state) do
    new_scroll = max(0, state.detail_scroll - 1)
    %{state | detail_scroll: new_scroll}
  end

  def move_down(%__MODULE__{active_panel: :projects, projects: projects} = state) do
    max_idx = max(0, length(projects) - 1)
    new_idx = min(max_idx, state.current_project + 1)

    %{state | current_project: new_idx}
    |> adjust_panel_scroll(:projects, new_idx)
  end

  def move_down(%__MODULE__{active_panel: :tickets, data: nil} = state), do: state

  def move_down(%__MODULE__{active_panel: :tickets, selected_ticket: nil, data: data} = state) do
    if data.tickets != [], do: %{state | selected_ticket: 0}, else: state
  end

  def move_down(%__MODULE__{active_panel: :tickets, data: data} = state) do
    max_idx = max(0, length(data.tickets) - 1)
    new_idx = min(max_idx, state.selected_ticket + 1)

    %{state | selected_ticket: new_idx}
    |> adjust_panel_scroll(:tickets, new_idx)
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
    |> adjust_panel_scroll(:research, new_idx)
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

  defdelegate enter_edit_mode(state), to: Editing
  defdelegate exit_edit_mode(state), to: Editing
  defdelegate next_edit_field(state), to: Editing
  defdelegate prev_edit_field(state), to: Editing
  def edit_insert_char(state, char), do: Editing.insert_char(state, char)
  def edit_delete_char(state), do: Editing.delete_char(state)
  def edit_move_cursor_left(state), do: Editing.move_cursor_left(state)
  def edit_move_cursor_right(state), do: Editing.move_cursor_right(state)
  def edit_cursor_home(state), do: Editing.cursor_home(state)
  def edit_cursor_end(state), do: Editing.cursor_end(state)
  defdelegate get_edit_changes(state), to: Editing

  defdelegate enter_input_mode(state, input_mode, prompt), to: Editing
  defdelegate exit_input_mode(state), to: Editing
  defdelegate input_insert_char(state, char), to: Editing
  defdelegate input_delete_char(state), to: Editing
  defdelegate input_move_cursor_left(state), to: Editing
  defdelegate input_move_cursor_right(state), to: Editing

  defdelegate enter_confirm_mode(state, action, message), to: Editing
  defdelegate exit_confirm_mode(state), to: Editing

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

  def enter_modal(state, type), do: Modal.enter(state, type)
  def start_modal_operation(state), do: Modal.start_operation(state)
  def add_modal_log(state, log), do: Modal.add_log(state, log)

  def update_agent_progress(state, current, total, name),
    do: Modal.update_agent_progress(state, current, total, name)

  def complete_modal(state, status, result), do: Modal.complete(state, status, result)
  def modal_insert_char(state, char), do: Modal.insert_char(state, char)
  def modal_delete_char(state), do: Modal.delete_char(state)
  def modal_move_cursor_left(state), do: Modal.move_cursor_left(state)
  def modal_move_cursor_right(state), do: Modal.move_cursor_right(state)
  def modal_next_field(state), do: Modal.next_field(state)
  def modal_prev_field(state), do: Modal.prev_field(state)
  def exit_modal(state), do: Modal.exit(state)
  def scroll_modal_up(state), do: Modal.scroll_up(state)
  def scroll_modal_down(state), do: Modal.scroll_down(state)

  defp adjust_panel_scroll(%{terminal_size: {_width, height}} = state, panel, selected_idx) do
    panel_height = height - 2
    section_height = div(panel_height, 3)
    visible_rows = section_height - 2

    current_scroll = Map.get(state.panel_scroll, panel, 0)

    new_scroll =
      cond do
        selected_idx < current_scroll ->
          selected_idx

        selected_idx >= current_scroll + visible_rows ->
          selected_idx - visible_rows + 1

        true ->
          current_scroll
      end

    updated_scroll = Map.put(state.panel_scroll, panel, max(0, new_scroll))
    %{state | panel_scroll: updated_scroll}
  end
end
