defmodule Albedo.TUI.State.Editing do
  @moduledoc """
  Editing state operations for edit mode, input mode, and confirm dialogs.
  """

  alias Albedo.TUI.State

  @editable_fields [:title, :description, :type, :priority, :estimate, :labels]

  def editable_fields, do: @editable_fields

  @doc """
  Enter edit mode for the current ticket.
  """
  def enter_edit_mode(%State{} = state) do
    case State.current_ticket(state) do
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

  @doc """
  Exit edit mode.
  """
  def exit_edit_mode(%State{} = state) do
    %{
      state
      | mode: :normal,
        edit_field: nil,
        edit_buffer: nil,
        edit_cursor: 0
    }
  end

  @doc """
  Move to the next editable field.
  """
  def next_edit_field(%State{edit_field: current} = state) do
    fields = @editable_fields
    current_idx = Enum.find_index(fields, &(&1 == current)) || 0
    next_idx = rem(current_idx + 1, length(fields))
    next_field = Enum.at(fields, next_idx)

    ticket = State.current_ticket(state)
    value = get_field_value(ticket, next_field)

    %{
      state
      | edit_field: next_field,
        edit_buffer: value,
        edit_cursor: String.length(value)
    }
  end

  @doc """
  Move to the previous editable field.
  """
  def prev_edit_field(%State{edit_field: current} = state) do
    fields = @editable_fields
    current_idx = Enum.find_index(fields, &(&1 == current)) || 0
    prev_idx = if current_idx == 0, do: length(fields) - 1, else: current_idx - 1
    prev_field = Enum.at(fields, prev_idx)

    ticket = State.current_ticket(state)
    value = get_field_value(ticket, prev_field)

    %{
      state
      | edit_field: prev_field,
        edit_buffer: value,
        edit_cursor: String.length(value)
    }
  end

  @doc """
  Insert a character at cursor position in edit buffer.
  """
  def insert_char(%State{edit_buffer: buffer, edit_cursor: cursor} = state, char) do
    {before, after_cursor} = String.split_at(buffer, cursor)
    new_buffer = before <> char <> after_cursor

    %{state | edit_buffer: new_buffer, edit_cursor: cursor + String.length(char)}
  end

  @doc """
  Delete character before cursor in edit buffer.
  """
  def delete_char(%State{edit_buffer: buffer, edit_cursor: cursor} = state) do
    if cursor > 0 do
      {before, after_cursor} = String.split_at(buffer, cursor)
      new_before = String.slice(before, 0, String.length(before) - 1)
      new_buffer = new_before <> after_cursor

      %{state | edit_buffer: new_buffer, edit_cursor: cursor - 1}
    else
      state
    end
  end

  @doc """
  Move edit cursor left.
  """
  def move_cursor_left(%State{edit_cursor: cursor} = state) do
    %{state | edit_cursor: max(0, cursor - 1)}
  end

  @doc """
  Move edit cursor right.
  """
  def move_cursor_right(%State{edit_buffer: buffer, edit_cursor: cursor} = state) do
    %{state | edit_cursor: min(String.length(buffer), cursor + 1)}
  end

  @doc """
  Move cursor to start of buffer.
  """
  def cursor_home(%State{} = state) do
    %{state | edit_cursor: 0}
  end

  @doc """
  Move cursor to end of buffer.
  """
  def cursor_end(%State{edit_buffer: buffer} = state) do
    %{state | edit_cursor: String.length(buffer)}
  end

  @doc """
  Get the changes made in edit mode.
  """
  def get_edit_changes(%State{edit_field: field, edit_buffer: buffer}) do
    %{field => parse_field_value(field, buffer)}
  end

  @doc """
  Enter input mode with a prompt.
  """
  def enter_input_mode(%State{} = state, input_mode, prompt) do
    %{
      state
      | mode: :input,
        input_mode: input_mode,
        input_prompt: prompt,
        input_buffer: "",
        input_cursor: 0
    }
  end

  @doc """
  Exit input mode.
  """
  def exit_input_mode(%State{} = state) do
    %{
      state
      | mode: :normal,
        input_mode: nil,
        input_prompt: nil,
        input_buffer: nil,
        input_cursor: 0
    }
  end

  @doc """
  Insert a character in input buffer.
  """
  def input_insert_char(%State{input_buffer: buffer, input_cursor: cursor} = state, char) do
    {before, after_cursor} = String.split_at(buffer, cursor)
    new_buffer = before <> char <> after_cursor
    %{state | input_buffer: new_buffer, input_cursor: cursor + String.length(char)}
  end

  @doc """
  Delete character before cursor in input buffer.
  """
  def input_delete_char(%State{input_buffer: buffer, input_cursor: cursor} = state) do
    if cursor > 0 do
      {before, after_cursor} = String.split_at(buffer, cursor)
      new_before = String.slice(before, 0, String.length(before) - 1)
      new_buffer = new_before <> after_cursor
      %{state | input_buffer: new_buffer, input_cursor: cursor - 1}
    else
      state
    end
  end

  @doc """
  Move input cursor left.
  """
  def input_move_cursor_left(%State{input_cursor: cursor} = state) do
    %{state | input_cursor: max(0, cursor - 1)}
  end

  @doc """
  Move input cursor right.
  """
  def input_move_cursor_right(%State{input_buffer: buffer, input_cursor: cursor} = state) do
    %{state | input_cursor: min(String.length(buffer), cursor + 1)}
  end

  @doc """
  Enter confirm mode with an action and message.
  """
  def enter_confirm_mode(%State{} = state, action, message) do
    %{
      state
      | mode: :confirm,
        confirm_action: action,
        confirm_message: message
    }
  end

  @doc """
  Exit confirm mode.
  """
  def exit_confirm_mode(%State{} = state) do
    %{
      state
      | mode: :normal,
        confirm_action: nil,
        confirm_message: nil
    }
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
end
