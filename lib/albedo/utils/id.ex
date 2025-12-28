defmodule Albedo.Utils.Id do
  @moduledoc """
  Shared ID generation utilities for projects and tickets.
  """

  @doc """
  Generates a project ID from a task description.

  Format: `YYYY-MM-DD_slug_XXXX` where:
  - YYYY-MM-DD is the current date
  - slug is the slugified task (max 30 chars)
  - XXXX is a 4-digit unique suffix

  ## Examples

      iex> Albedo.Utils.Id.generate_project_id("Add user authentication")
      "2025-01-15_add-user-authentication_1234"

      iex> Albedo.Utils.Id.generate_project_id("Task", "custom-name")
      "custom-name"
  """
  def generate_project_id(task, custom_name \\ nil)

  def generate_project_id(_task, custom_name)
      when is_binary(custom_name) and custom_name != "" do
    custom_name
    |> String.downcase()
    |> slugify()
  end

  def generate_project_id(task, _custom_name) do
    date = Date.utc_today() |> Date.to_iso8601()
    slug = task |> String.downcase() |> String.slice(0, 30) |> slugify()
    suffix = unique_suffix()

    "#{date}_#{slug}_#{suffix}"
  end

  @doc """
  Generates a unique project ID from a name, checking for duplicates.

  The name is slugified (spaces become hyphens, lowercase).
  If a duplicate exists, appends -1, -2, etc.

  ## Examples

      iex> Albedo.Utils.Id.generate_unique_project_id("My Project", [])
      "my-project"

      iex> Albedo.Utils.Id.generate_unique_project_id("My Project", ["my-project"])
      "my-project-1"

      iex> Albedo.Utils.Id.generate_unique_project_id("My Project", ["my-project", "my-project-1"])
      "my-project-2"
  """
  def generate_unique_project_id(name, existing_ids)
      when is_binary(name) and is_list(existing_ids) do
    base_id = slugify(name)
    find_unique_id(base_id, existing_ids)
  end

  defp find_unique_id(base_id, existing_ids) do
    if base_id in existing_ids do
      find_unique_id_with_suffix(base_id, existing_ids, 1)
    else
      base_id
    end
  end

  defp find_unique_id_with_suffix(base_id, existing_ids, n) do
    candidate = "#{base_id}-#{n}"

    if candidate in existing_ids do
      find_unique_id_with_suffix(base_id, existing_ids, n + 1)
    else
      candidate
    end
  end

  @doc """
  Computes the next ticket ID from a list of tickets.

  Finds the maximum numeric ID and returns the next integer as a string.

  ## Examples

      iex> Albedo.Utils.Id.next_ticket_id([%{id: "1"}, %{id: "2"}])
      "3"

      iex> Albedo.Utils.Id.next_ticket_id([])
      "1"
  """
  def next_ticket_id(tickets) when is_list(tickets) do
    max_id =
      tickets
      |> Enum.map(&parse_numeric_id/1)
      |> Enum.max(fn -> 0 end)

    to_string(max_id + 1)
  end

  @doc """
  Parses a numeric ID from a ticket or map with an :id field.

  Returns 0 for non-numeric or missing IDs.

  ## Examples

      iex> Albedo.Utils.Id.parse_numeric_id(%{id: "5"})
      5

      iex> Albedo.Utils.Id.parse_numeric_id(%{id: "abc"})
      0
  """
  def parse_numeric_id(%{id: id}) when is_binary(id) do
    case Integer.parse(id) do
      {num, _} -> num
      :error -> 0
    end
  end

  def parse_numeric_id(_), do: 0

  @doc """
  Converts a string to a URL-safe slug.

  Replaces non-alphanumeric characters with hyphens and trims leading/trailing hyphens.

  ## Examples

      iex> Albedo.Utils.Id.slugify("Hello World!")
      "hello-world"

      iex> Albedo.Utils.Id.slugify("Add user authentication")
      "add-user-authentication"
  """
  def slugify(string) when is_binary(string) do
    string
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  def slugify(_), do: ""

  defp unique_suffix do
    :erlang.unique_integer([:positive])
    |> rem(10_000)
    |> Integer.to_string()
    |> String.pad_leading(4, "0")
  end
end
