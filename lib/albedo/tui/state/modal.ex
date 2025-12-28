defmodule Albedo.TUI.State.Modal do
  @moduledoc """
  Modal dialog state operations for Plan and Analyze workflows.
  """

  alias Albedo.TUI.State

  @doc """
  Enter a modal dialog (plan or analyze).
  """
  def enter(%State{} = state, type) do
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

  @doc """
  Start the modal operation (transitions from input to running phase).
  """
  def start_operation(%State{modal_data: data} = state) do
    updated_data = %{
      data
      | phase: :running,
        name: data.name_buffer,
        task: data.task_buffer,
        logs: ["Starting #{data.type}..."]
    }

    %{state | modal_data: updated_data}
  end

  @doc """
  Add a log entry to the modal.
  """
  def add_log(%State{modal_data: nil} = state, _log), do: state

  def add_log(%State{modal_data: data} = state, log) do
    updated_data = %{data | logs: data.logs ++ [log]}
    %{state | modal_data: updated_data}
  end

  @doc """
  Update agent progress in the modal.
  """
  def update_agent_progress(%State{modal_data: nil} = state, _current, _total, _name),
    do: state

  def update_agent_progress(%State{modal_data: data} = state, current, total, name) do
    updated_data = %{data | current_agent: current, total_agents: total, agent_name: name}
    %{state | modal_data: updated_data}
  end

  @doc """
  Complete the modal operation.
  """
  def complete(%State{modal_data: nil} = state, _status, _result), do: state

  def complete(%State{modal_data: data} = state, status, result) do
    updated_data = %{data | phase: status, result: result}
    %{state | modal_data: updated_data}
  end

  @doc """
  Insert a character at cursor position in the active modal field.
  """
  def insert_char(%State{modal_data: data} = state, char) do
    {buffer_key, buffer} = get_active_buffer(data)
    cursor = data.cursor
    {before, after_cursor} = String.split_at(buffer, cursor)
    new_buffer = before <> char <> after_cursor
    updated_data = Map.put(data, buffer_key, new_buffer) |> Map.put(:cursor, cursor + 1)
    %{state | modal_data: updated_data}
  end

  @doc """
  Delete character before cursor in the active modal field.
  """
  def delete_char(%State{modal_data: %{cursor: 0}} = state), do: state

  def delete_char(%State{modal_data: data} = state) do
    {buffer_key, buffer} = get_active_buffer(data)
    cursor = data.cursor
    {before, after_cursor} = String.split_at(buffer, cursor)
    new_before = String.slice(before, 0, String.length(before) - 1)
    new_buffer = new_before <> after_cursor
    updated_data = Map.put(data, buffer_key, new_buffer) |> Map.put(:cursor, cursor - 1)
    %{state | modal_data: updated_data}
  end

  @doc """
  Move cursor left in modal field.
  """
  def move_cursor_left(%State{modal_data: data} = state) do
    updated_data = %{data | cursor: max(0, data.cursor - 1)}
    %{state | modal_data: updated_data}
  end

  @doc """
  Move cursor right in modal field.
  """
  def move_cursor_right(%State{modal_data: data} = state) do
    {_buffer_key, buffer} = get_active_buffer(data)
    updated_data = %{data | cursor: min(String.length(buffer), data.cursor + 1)}
    %{state | modal_data: updated_data}
  end

  @doc """
  Move to the next modal field.
  """
  def next_field(%State{modal: :analyze, modal_data: %{active_field: :name} = data} = state) do
    updated_data = %{data | active_field: :title, cursor: String.length(data.title_buffer)}
    %{state | modal_data: updated_data}
  end

  def next_field(%State{modal: :analyze, modal_data: %{active_field: :title} = data} = state) do
    updated_data = %{data | active_field: :task, cursor: String.length(data.task_buffer)}
    %{state | modal_data: updated_data}
  end

  def next_field(%State{modal: :analyze, modal_data: %{active_field: :task} = data} = state) do
    updated_data = %{data | active_field: :name, cursor: String.length(data.name_buffer)}
    %{state | modal_data: updated_data}
  end

  def next_field(%State{modal_data: %{active_field: :name} = data} = state) do
    updated_data = %{data | active_field: :task, cursor: String.length(data.task_buffer)}
    %{state | modal_data: updated_data}
  end

  def next_field(%State{modal_data: %{active_field: :task} = data} = state) do
    updated_data = %{data | active_field: :name, cursor: String.length(data.name_buffer)}
    %{state | modal_data: updated_data}
  end

  @doc """
  Move to the previous modal field.
  """
  def prev_field(%State{modal_data: data} = state) do
    next_field(%{state | modal_data: data})
  end

  @doc """
  Exit the modal and return to normal mode.
  """
  def exit(%State{} = state) do
    %{
      state
      | mode: :normal,
        modal: nil,
        modal_data: nil,
        modal_scroll: 0,
        modal_task_ref: nil
    }
  end

  @doc """
  Scroll modal logs up.
  """
  def scroll_up(%State{modal_scroll: scroll} = state) do
    %{state | modal_scroll: max(0, scroll - 1)}
  end

  @doc """
  Scroll modal logs down.
  """
  def scroll_down(%State{modal_data: nil} = state), do: state

  def scroll_down(%State{modal_scroll: scroll, modal_data: data} = state) do
    max_scroll = max(0, length(data.logs) - 1)
    %{state | modal_scroll: min(max_scroll, scroll + 1)}
  end

  defp get_active_buffer(%{active_field: :name, name_buffer: buffer}),
    do: {:name_buffer, buffer}

  defp get_active_buffer(%{active_field: :title, title_buffer: buffer}),
    do: {:title_buffer, buffer}

  defp get_active_buffer(%{active_field: :task, task_buffer: buffer}),
    do: {:task_buffer, buffer}
end
