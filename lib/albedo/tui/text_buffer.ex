defmodule Albedo.TUI.TextBuffer do
  @moduledoc """
  Shared text buffer manipulation functions for TUI edit, input, and modal modes.
  Reduces duplication of cursor movement and character insertion/deletion logic.
  """

  @type buffer_state :: %{buffer: String.t(), cursor: non_neg_integer()}

  @doc """
  Inserts a character at the cursor position.

  ## Examples

      iex> TextBuffer.insert_char(%{buffer: "hello", cursor: 2}, "X")
      %{buffer: "heXllo", cursor: 3}
  """
  @spec insert_char(buffer_state(), String.t()) :: buffer_state()
  def insert_char(%{buffer: buffer, cursor: cursor} = state, char) do
    {before, after_cursor} = String.split_at(buffer, cursor)
    new_buffer = before <> char <> after_cursor

    %{state | buffer: new_buffer, cursor: cursor + String.length(char)}
  end

  @doc """
  Deletes the character before the cursor (backspace behavior).

  ## Examples

      iex> TextBuffer.delete_char(%{buffer: "hello", cursor: 2})
      %{buffer: "hllo", cursor: 1}

      iex> TextBuffer.delete_char(%{buffer: "hello", cursor: 0})
      %{buffer: "hello", cursor: 0}
  """
  @spec delete_char(buffer_state()) :: buffer_state()
  def delete_char(%{cursor: 0} = state), do: state

  def delete_char(%{buffer: buffer, cursor: cursor} = state) do
    {before, after_cursor} = String.split_at(buffer, cursor)
    new_before = String.slice(before, 0, String.length(before) - 1)
    new_buffer = new_before <> after_cursor

    %{state | buffer: new_buffer, cursor: cursor - 1}
  end

  @doc """
  Moves the cursor one position to the left.

  ## Examples

      iex> TextBuffer.move_cursor_left(%{buffer: "hello", cursor: 3})
      %{buffer: "hello", cursor: 2}

      iex> TextBuffer.move_cursor_left(%{buffer: "hello", cursor: 0})
      %{buffer: "hello", cursor: 0}
  """
  @spec move_cursor_left(buffer_state()) :: buffer_state()
  def move_cursor_left(%{cursor: cursor} = state) do
    %{state | cursor: max(0, cursor - 1)}
  end

  @doc """
  Moves the cursor one position to the right.

  ## Examples

      iex> TextBuffer.move_cursor_right(%{buffer: "hello", cursor: 2})
      %{buffer: "hello", cursor: 3}

      iex> TextBuffer.move_cursor_right(%{buffer: "hello", cursor: 5})
      %{buffer: "hello", cursor: 5}
  """
  @spec move_cursor_right(buffer_state()) :: buffer_state()
  def move_cursor_right(%{buffer: buffer, cursor: cursor} = state) do
    %{state | cursor: min(String.length(buffer), cursor + 1)}
  end

  @doc """
  Moves cursor to the beginning of the buffer.
  """
  @spec cursor_home(buffer_state()) :: buffer_state()
  def cursor_home(state), do: %{state | cursor: 0}

  @doc """
  Moves cursor to the end of the buffer.
  """
  @spec cursor_end(buffer_state()) :: buffer_state()
  def cursor_end(%{buffer: buffer} = state) do
    %{state | cursor: String.length(buffer)}
  end
end
