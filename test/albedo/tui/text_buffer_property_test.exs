defmodule Albedo.TUI.TextBufferPropertyTest do
  use ExUnit.Case, async: true
  use PropCheck

  alias Albedo.TUI.TextBuffer

  describe "insert_char/2 properties" do
    property "buffer grows by char length" do
      forall {buffer, cursor, char} <- {ascii_string(), non_neg_integer(), printable_char()} do
        cursor = min(cursor, String.length(buffer))
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.insert_char(state, char)

        String.length(result.buffer) == String.length(buffer) + String.length(char)
      end
    end

    property "cursor advances by char length" do
      forall {buffer, cursor, char} <- {ascii_string(), non_neg_integer(), printable_char()} do
        cursor = min(cursor, String.length(buffer))
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.insert_char(state, char)

        result.cursor == cursor + String.length(char)
      end
    end

    property "char appears at cursor position" do
      forall {buffer, cursor, char} <- {ascii_string(), non_neg_integer(), printable_char()} do
        cursor = min(cursor, String.length(buffer))
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.insert_char(state, char)

        String.at(result.buffer, cursor) == String.at(char, 0)
      end
    end

    property "content before cursor is preserved" do
      forall {buffer, cursor, char} <- {ascii_string(), non_neg_integer(), printable_char()} do
        cursor = min(cursor, String.length(buffer))
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.insert_char(state, char)

        String.slice(result.buffer, 0, cursor) == String.slice(buffer, 0, cursor)
      end
    end
  end

  describe "delete_char/1 properties" do
    property "cursor at 0 does nothing" do
      forall buffer <- ascii_string() do
        state = %{buffer: buffer, cursor: 0}
        result = TextBuffer.delete_char(state)

        result.buffer == buffer and result.cursor == 0
      end
    end

    property "buffer shrinks by 1 when cursor > 0" do
      forall buffer <- non_empty_ascii_string() do
        cursor = String.length(buffer)
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.delete_char(state)

        String.length(result.buffer) == String.length(buffer) - 1
      end
    end

    property "cursor decrements by 1 when cursor > 0" do
      forall buffer <- non_empty_ascii_string() do
        cursor = String.length(buffer)
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.delete_char(state)

        result.cursor == cursor - 1
      end
    end

    property "content after cursor is preserved" do
      forall {buffer, cursor} <- {min_length_ascii_string(2), pos_integer()} do
        cursor = min(cursor, String.length(buffer))
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.delete_char(state)

        if cursor > 0 do
          after_cursor_original = String.slice(buffer, cursor, String.length(buffer))

          after_cursor_result =
            String.slice(result.buffer, cursor - 1, String.length(result.buffer))

          after_cursor_original == after_cursor_result
        else
          true
        end
      end
    end
  end

  describe "move_cursor_left/1 properties" do
    property "cursor never goes below 0" do
      forall {buffer, cursor} <- {ascii_string(), non_neg_integer()} do
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.move_cursor_left(state)

        result.cursor >= 0
      end
    end

    property "cursor decrements by 1 when > 0" do
      forall {buffer, cursor} <- {ascii_string(), pos_integer()} do
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.move_cursor_left(state)

        result.cursor == cursor - 1
      end
    end

    property "buffer is unchanged" do
      forall {buffer, cursor} <- {ascii_string(), non_neg_integer()} do
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.move_cursor_left(state)

        result.buffer == buffer
      end
    end
  end

  describe "move_cursor_right/1 properties" do
    property "cursor never exceeds buffer length" do
      forall {buffer, cursor} <- {ascii_string(), non_neg_integer()} do
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.move_cursor_right(state)

        result.cursor <= String.length(buffer)
      end
    end

    property "cursor increments by 1 when < buffer length" do
      forall buffer <- non_empty_ascii_string() do
        cursor = 0
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.move_cursor_right(state)

        result.cursor == 1
      end
    end

    property "buffer is unchanged" do
      forall {buffer, cursor} <- {ascii_string(), non_neg_integer()} do
        state = %{buffer: buffer, cursor: cursor}
        result = TextBuffer.move_cursor_right(state)

        result.buffer == buffer
      end
    end
  end

  describe "cursor movement roundtrip" do
    property "left then right at middle returns to same position" do
      forall buffer <- min_length_ascii_string(2) do
        cursor = div(String.length(buffer), 2)
        state = %{buffer: buffer, cursor: cursor}

        result =
          state
          |> TextBuffer.move_cursor_left()
          |> TextBuffer.move_cursor_right()

        result.cursor == cursor
      end
    end

    property "insert then delete restores original buffer" do
      forall {buffer, char} <- {ascii_string(), printable_char()} do
        cursor = String.length(buffer)
        state = %{buffer: buffer, cursor: cursor}

        result =
          state
          |> TextBuffer.insert_char(char)
          |> TextBuffer.delete_char()

        result.buffer == buffer
      end
    end
  end

  defp printable_char do
    let c <- choose(32, 126) do
      <<c::utf8>>
    end
  end

  defp ascii_string do
    let chars <- list(choose(32, 126)) do
      List.to_string(chars)
    end
  end

  defp non_empty_ascii_string do
    let chars <- non_empty(list(choose(32, 126))) do
      List.to_string(chars)
    end
  end

  defp min_length_ascii_string(min) do
    let chars <- vector(min + :rand.uniform(10), choose(32, 126)) do
      List.to_string(chars)
    end
  end
end
