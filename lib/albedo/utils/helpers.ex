defmodule Albedo.Utils.Helpers do
  @moduledoc """
  Common utility functions used across the Albedo codebase.
  """

  @doc """
  Removes nil values from a list.

  ## Examples

      iex> Albedo.Utils.Helpers.compact([1, nil, 2, nil, 3])
      [1, 2, 3]

      iex> Albedo.Utils.Helpers.compact([nil, nil])
      []
  """
  @spec compact(list()) :: list()
  def compact(list) when is_list(list) do
    Enum.reject(list, &is_nil/1)
  end

  @doc """
  Reads a file and returns content wrapped in a list, or empty list on failure.
  Useful for flat_map operations when collecting optional file contents.

  ## Examples

      iex> Albedo.Utils.Helpers.read_file_to_list("/path/to/existing/file")
      ["file content here"]

      iex> Albedo.Utils.Helpers.read_file_to_list("/nonexistent")
      []
  """
  @spec read_file_to_list(Path.t()) :: [String.t()]
  def read_file_to_list(path) do
    case File.read(path) do
      {:ok, content} -> [content]
      {:error, _} -> []
    end
  end

  @doc """
  Returns the value if not nil, otherwise returns the default.
  Shorthand for `value || default` with explicit nil check.

  ## Examples

      iex> Albedo.Utils.Helpers.default_value(nil, [])
      []

      iex> Albedo.Utils.Helpers.default_value("hello", [])
      "hello"
  """
  @spec default_value(term(), term()) :: term()
  def default_value(nil, default), do: default
  def default_value(value, _default), do: value

  @doc """
  Returns value as a list, defaulting to empty list if nil.

  ## Examples

      iex> Albedo.Utils.Helpers.default_list(nil)
      []

      iex> Albedo.Utils.Helpers.default_list([1, 2, 3])
      [1, 2, 3]
  """
  @spec default_list(list() | nil) :: list()
  def default_list(nil), do: []
  def default_list(list) when is_list(list), do: list

  @doc """
  Checks if a path is safe (no path traversal attempts).
  Returns true if the path doesn't contain traversal sequences.

  ## Examples

      iex> Albedo.Utils.Helpers.safe_path?("my-project")
      true

      iex> Albedo.Utils.Helpers.safe_path?("../../../etc/passwd")
      false

      iex> Albedo.Utils.Helpers.safe_path?("foo/../bar")
      false
  """
  @spec safe_path?(String.t()) :: boolean()
  def safe_path?(path) when is_binary(path) do
    not String.contains?(path, ["../", "..\\", ".."]) and
      not String.starts_with?(path, "/") and
      not String.starts_with?(path, "~")
  end

  def safe_path?(_), do: false

  @doc """
  Validates that a path component (directory name or filename) is safe.
  For use when joining user-provided path components.

  ## Examples

      iex> Albedo.Utils.Helpers.safe_path_component?("my-project-123")
      true

      iex> Albedo.Utils.Helpers.safe_path_component?("..")
      false

      iex> Albedo.Utils.Helpers.safe_path_component?("foo/bar")
      false
  """
  @spec safe_path_component?(String.t()) :: boolean()
  def safe_path_component?(component) when is_binary(component) do
    component != "" and
      component != "." and
      component != ".." and
      not String.contains?(component, ["/", "\\", "\0"])
  end

  def safe_path_component?(_), do: false
end
