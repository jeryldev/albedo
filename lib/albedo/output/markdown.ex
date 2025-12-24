defmodule Albedo.Output.Markdown do
  @moduledoc """
  Markdown formatting utilities for output generation.
  """

  @doc """
  Create a markdown heading.
  """
  def heading(text, level \\ 1) do
    prefix = String.duplicate("#", level)
    "#{prefix} #{text}\n"
  end

  @doc """
  Create a markdown table.
  """
  def table(headers, rows) when is_list(headers) and is_list(rows) do
    header_row = "| " <> Enum.join(headers, " | ") <> " |"
    separator = "| " <> Enum.map_join(headers, " | ", fn _ -> "---" end) <> " |"

    data_rows =
      Enum.map_join(rows, "\n", fn row ->
        "| " <> Enum.map_join(row, " | ", &escape_cell/1) <> " |"
      end)

    """
    #{header_row}
    #{separator}
    #{data_rows}
    """
  end

  @doc """
  Create a code block.
  """
  def code_block(content, language \\ "") do
    """
    ```#{language}
    #{content}
    ```
    """
  end

  @doc """
  Create an inline code span.
  """
  def code(text) do
    "`#{text}`"
  end

  @doc """
  Create a bullet list.
  """
  def bullet_list(items) when is_list(items) do
    Enum.map_join(items, "\n", &"- #{&1}")
  end

  @doc """
  Create a numbered list.
  """
  def numbered_list(items) when is_list(items) do
    items
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {item, idx} -> "#{idx}. #{item}" end)
  end

  @doc """
  Create a checkbox list.
  """
  def checkbox_list(items, checked \\ []) when is_list(items) do
    Enum.map_join(items, "\n", fn item ->
      box = if item in checked, do: "[x]", else: "[ ]"
      "- #{box} #{item}"
    end)
  end

  @doc """
  Create a blockquote.
  """
  def blockquote(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &"> #{&1}")
  end

  @doc """
  Create a horizontal rule.
  """
  def horizontal_rule do
    "\n---\n"
  end

  @doc """
  Create a link.
  """
  def link(text, url) do
    "[#{text}](#{url})"
  end

  @doc """
  Create bold text.
  """
  def bold(text) do
    "**#{text}**"
  end

  @doc """
  Create italic text.
  """
  def italic(text) do
    "*#{text}*"
  end

  @doc """
  Create a mermaid diagram.
  """
  def mermaid(diagram_content) do
    """
    ```mermaid
    #{diagram_content}
    ```
    """
  end

  @doc """
  Create a collapsible section (details/summary).
  """
  def collapsible(summary, content) do
    """
    <details>
    <summary>#{summary}</summary>

    #{content}

    </details>
    """
  end

  @doc """
  Escape special markdown characters in table cells.
  """
  def escape_cell(text) when is_binary(text) do
    text
    |> String.replace("|", "\\|")
    |> String.replace("\n", " ")
  end

  def escape_cell(other), do: to_string(other)

  @doc """
  Join sections with proper spacing.
  """
  def join_sections(sections) when is_list(sections) do
    sections
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join("\n\n")
  end
end
