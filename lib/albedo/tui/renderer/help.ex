defmodule Albedo.TUI.Renderer.Help do
  @moduledoc """
  Renders the help screen overlay for the TUI.
  """

  alias Albedo.TUI.Renderer.Utils

  @help_content [
    {:header, "Keyboard Shortcuts"},
    {:blank},
    {:section, "Navigation"},
    {:key, "j / ↓", "Move down"},
    {:key, "k / ↑", "Move up"},
    {:key, "h / ←", "Previous panel"},
    {:key, "l / → / Tab", "Next panel"},
    {:key, "1 / 2 / 3 / 4", "Jump to panel (Projects/Tickets/Research/Detail)"},
    {:blank},
    {:section, "Projects Panel"},
    {:key, "Enter", "Load project tickets"},
    {:key, "n", "Create empty project"},
    {:key, "p", "Plan new project (AI)"},
    {:key, "a", "Analyze codebase (AI)"},
    {:key, "e", "Edit project task"},
    {:key, "x / X", "Delete project"},
    {:key, "R", "Refresh project list"},
    {:blank},
    {:section, "Tickets / Research"},
    {:key, "Enter", "View in detail panel"},
    {:key, "s", "Start ticket (in-progress)"},
    {:key, "d", "Done (completed)"},
    {:key, "r", "Reset ticket to pending"},
    {:key, "n", "Create new ticket"},
    {:key, "e", "Edit ticket"},
    {:key, "x / X", "Delete ticket"},
    {:blank},
    {:section, "Detail Panel"},
    {:key, "j / k", "Scroll content"},
    {:key, "n", "Create new ticket"},
    {:key, "e", "Edit ticket"},
    {:blank},
    {:section, "Edit Mode"},
    {:key, "Tab", "Next field"},
    {:key, "Shift+Tab", "Previous field"},
    {:key, "Enter", "Save changes"},
    {:key, "Esc", "Cancel edit"},
    {:blank},
    {:section, "General"},
    {:key, "?", "Show/hide this help"},
    {:key, "q / Q", "Quit"},
    {:blank},
    {:footer, "Press Esc, Enter, or ? to close"}
  ]

  def build_help_line(row, _state, width, height) do
    colors = Utils.colors()
    content_start = 3
    content_end = height - 2

    cond do
      row == 1 ->
        title = " Help "
        colors.bold <> colors.green <> String.pad_trailing(title, width) <> colors.reset

      row == 2 or row == height - 1 ->
        colors.dim <> String.duplicate("─", width) <> colors.reset

      row == height ->
        colors.dim <>
          String.pad_trailing(" Press Esc, Enter, or ? to close ", width) <> colors.reset

      row >= content_start and row <= content_end ->
        help_row = row - content_start
        render_help_content_line(help_row, width)

      true ->
        String.duplicate(" ", width)
    end
  end

  defp render_help_content_line(row, width) do
    colors = Utils.colors()

    case Enum.at(@help_content, row) do
      nil ->
        String.duplicate(" ", width)

      {:header, text} ->
        colors.bold <>
          colors.green <>
          String.pad_trailing("  " <> text, width) <> colors.reset

      {:blank} ->
        String.duplicate(" ", width)

      {:section, title} ->
        colors.bold <>
          colors.yellow <>
          String.pad_trailing("  " <> title, width) <> colors.reset

      {:key, key, desc} ->
        padded_key = String.pad_trailing(key, 16)

        "    " <>
          colors.green <>
          padded_key <>
          colors.reset <>
          String.pad_trailing(desc, width - 20)

      {:footer, text} ->
        colors.dim <> String.pad_trailing("  " <> text, width) <> colors.reset
    end
  end
end
