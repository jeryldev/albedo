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
end
