defmodule Albedo.TUI.Terminal do
  @moduledoc """
  Raw terminal I/O handling for the TUI.
  Manages terminal mode switching and input reading.
  Uses OTP 28+ native raw terminal mode.
  """

  @doc """
  Enables raw mode on the terminal for character-by-character input.
  Uses OTP 28's native shell raw mode.
  """
  def enable_raw_mode do
    try do
      :shell.start_interactive({:noshell, :raw})
      {:ok, :raw_mode}
    rescue
      _ -> {:error, :not_a_tty}
    catch
      _, _ -> {:error, :not_a_tty}
    end
  end

  @doc """
  Restores the terminal to cooked (normal) mode.
  """
  def restore_mode(:raw_mode) do
    try do
      :shell.start_interactive({:noshell, :cooked})
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    :ok
  end

  def restore_mode(_), do: :ok

  @doc """
  Clears the screen and moves cursor to home position.
  """
  def clear_screen do
    IO.write("\e[2J\e[H")
  end

  @doc """
  Moves cursor to the specified position (1-indexed).
  """
  def move_cursor(row, col) do
    IO.write("\e[#{row};#{col}H")
  end

  @doc """
  Hides the cursor.
  """
  def hide_cursor do
    IO.write("\e[?25l")
  end

  @doc """
  Shows the cursor.
  """
  def show_cursor do
    IO.write("\e[?25h")
  end

  @doc """
  Gets the current terminal size.
  Returns {width, height}.
  """
  def get_size do
    case :io.columns() do
      {:ok, cols} ->
        case :io.rows() do
          {:ok, rows} -> {cols, rows}
          _ -> {80, 24}
        end

      _ ->
        {80, 24}
    end
  end

  @doc """
  Enables alternate screen buffer.
  """
  def enter_alternate_screen do
    IO.write("\e[?1049h")
  end

  @doc """
  Exits alternate screen buffer.
  """
  def exit_alternate_screen do
    IO.write("\e[?1049l")
  end

  @doc """
  Reads a single character from stdin in raw mode.
  Returns the character or a tuple for special keys.
  """
  def read_char do
    case IO.getn("", 1) do
      "\e" -> read_escape_sequence()
      char -> parse_char(char)
    end
  end

  defp read_escape_sequence do
    case IO.getn("", 1) do
      "[" -> read_csi_sequence()
      "\e" -> :escape
      "" -> :escape
      _ -> :escape
    end
  end

  defp read_csi_sequence do
    IO.getn("", 1) |> parse_csi_char()
  end

  defp parse_csi_char("A"), do: :up
  defp parse_csi_char("B"), do: :down
  defp parse_csi_char("C"), do: :right
  defp parse_csi_char("D"), do: :left
  defp parse_csi_char("H"), do: :home
  defp parse_csi_char("F"), do: :end
  defp parse_csi_char("Z"), do: :shift_tab
  defp parse_csi_char("5"), do: read_page_key(:page_up)
  defp parse_csi_char("6"), do: read_page_key(:page_down)
  defp parse_csi_char(c) when c in ["1", "7"], do: read_home_end_key(:home)
  defp parse_csi_char(c) when c in ["4", "8"], do: read_home_end_key(:end)
  defp parse_csi_char("2"), do: read_tilde_key(:insert)
  defp parse_csi_char("3"), do: read_tilde_key(:delete)
  defp parse_csi_char(_), do: :unknown

  defp read_page_key(key) do
    if IO.getn("", 1) == "~", do: key, else: :unknown
  end

  defp read_home_end_key(key) do
    if IO.getn("", 1) == "~", do: key, else: :unknown
  end

  defp read_tilde_key(key) do
    if IO.getn("", 1) == "~", do: key, else: :unknown
  end

  defp parse_char(<<3>>), do: :ctrl_c
  defp parse_char(<<4>>), do: :ctrl_d
  defp parse_char(<<9>>), do: :tab
  defp parse_char(<<13>>), do: :enter
  defp parse_char(<<127>>), do: :backspace
  defp parse_char(char), do: {:char, char}
end
