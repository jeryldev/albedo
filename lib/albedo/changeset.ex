defmodule Albedo.Changeset do
  @moduledoc """
  Lightweight schemaless changeset for data validation and casting.
  Inspired by Ecto.Changeset patterns for consistent validation without Ecto dependency.

  ## Usage

      defmodule MySchema do
        @types %{
          name: :string,
          age: :integer,
          status: {:enum, [:active, :inactive]}
        }

        def changeset(data \\\\ %{}, attrs) do
          {data, @types}
          |> Changeset.cast(attrs, [:name, :age, :status])
          |> Changeset.validate_required([:name])
        end
      end

  ## Supported Types

  - `:string` - Strings, trimmed automatically
  - `:integer` - Integers
  - `:boolean` - Booleans
  - `:atom` - Atoms only (rejects strings; use `{:enum, values}` for string input)
  - `{:enum, values}` - Enum with allowed values
  - `{:enum, values, mapping}` - Enum with string-to-atom mapping
  - `:list` - Lists (comma-separated strings parsed)
  - `:datetime` - DateTime (ISO8601 strings parsed)
  - `:map` - Maps (passed through)
  """

  defstruct [:data, :changes, :errors, :types, :valid?]

  @type t :: %__MODULE__{
          data: map(),
          changes: map(),
          errors: [{atom(), {String.t(), keyword()}}],
          types: map(),
          valid?: boolean()
        }

  @doc """
  Creates a new changeset from data and types, casting the given params.

  ## Examples

      iex> {%{name: nil}, %{name: :string}}
      ...> |> Changeset.cast(%{name: "Alice"}, [:name])
      %Changeset{changes: %{name: "Alice"}, valid?: true}
  """
  def cast({data, types}, params, permitted) when is_map(data) and is_map(types) do
    params = normalize_params(params)

    {changes, errors} =
      permitted
      |> Enum.reduce({%{}, []}, fn field, {changes_acc, errors_acc} ->
        type = Map.get(types, field)
        value = get_param(params, field)

        case cast_field(field, value, type) do
          {:ok, nil} ->
            {changes_acc, errors_acc}

          {:ok, cast_value} ->
            {Map.put(changes_acc, field, cast_value), errors_acc}

          {:error, message} ->
            {changes_acc, [{field, {message, []}} | errors_acc]}
        end
      end)

    %__MODULE__{
      data: data,
      changes: changes,
      errors: Enum.reverse(errors),
      types: types,
      valid?: errors == []
    }
  end

  @doc """
  Validates that required fields are present in the changeset.
  """
  def validate_required(%__MODULE__{} = changeset, fields) when is_list(fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      value = get_field(cs, field)

      if blank?(value) do
        add_error(cs, field, "can't be blank")
      else
        cs
      end
    end)
  end

  @doc """
  Adds an error to the changeset.
  """
  def add_error(%__MODULE__{} = changeset, field, message, keys \\ []) do
    %{changeset | errors: changeset.errors ++ [{field, {message, keys}}], valid?: false}
  end

  @doc """
  Gets a field value, checking changes first, then data.
  """
  def get_field(%__MODULE__{} = changeset, field) do
    case Map.fetch(changeset.changes, field) do
      {:ok, value} -> value
      :error -> Map.get(changeset.data, field)
    end
  end

  @doc """
  Gets a change value, or nil if not changed.
  """
  def get_change(%__MODULE__{} = changeset, field, default \\ nil) do
    Map.get(changeset.changes, field, default)
  end

  @doc """
  Puts a change into the changeset.
  """
  def put_change(%__MODULE__{} = changeset, field, value) do
    %{changeset | changes: Map.put(changeset.changes, field, value)}
  end

  @doc """
  Applies changes to data, returning the updated data map.
  Does not check validity - use apply_action/2 for that.
  """
  def apply_changes(%__MODULE__{data: data, changes: changes}) do
    Map.merge(data, changes)
  end

  @doc """
  Applies the changeset with an action, returning {:ok, data} or {:error, changeset}.
  """
  def apply_action(%__MODULE__{valid?: true} = changeset, _action) do
    {:ok, apply_changes(changeset)}
  end

  def apply_action(%__MODULE__{valid?: false} = changeset, _action) do
    {:error, changeset}
  end

  defp normalize_params(params) when is_map(params), do: params
  defp normalize_params(_), do: %{}

  defp get_param(params, field) do
    Map.get(params, field) || Map.get(params, to_string(field))
  end

  defp cast_field(_field, nil, _type), do: {:ok, nil}
  defp cast_field(_field, "", _type), do: {:ok, nil}

  defp cast_field(_field, value, :string) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: {:ok, nil}, else: {:ok, trimmed}
  end

  defp cast_field(_field, value, :integer) when is_integer(value), do: {:ok, value}

  defp cast_field(field, value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "#{field} is not a valid integer"}
    end
  end

  defp cast_field(_field, value, :boolean) when is_boolean(value), do: {:ok, value}

  defp cast_field(field, value, :boolean) when is_binary(value) do
    case String.downcase(value) do
      v when v in ["true", "1", "yes"] -> {:ok, true}
      v when v in ["false", "0", "no"] -> {:ok, false}
      _ -> {:error, "#{field} is not a valid boolean"}
    end
  end

  defp cast_field(_field, value, :atom) when is_atom(value), do: {:ok, value}

  defp cast_field(field, _value, :atom) do
    {:error, "#{field} must be an atom (use {:enum, values} for string conversion)"}
  end

  defp cast_field(field, value, {:enum, allowed}) when is_atom(value) do
    if Enum.member?(allowed, value), do: {:ok, value}, else: {:error, "#{field} is invalid"}
  end

  defp cast_field(field, value, {:enum, allowed}) when is_binary(value) do
    downcased = String.downcase(value)

    case Enum.find(allowed, fn atom -> Atom.to_string(atom) == downcased end) do
      nil -> {:error, "#{field} is invalid"}
      atom -> {:ok, atom}
    end
  end

  defp cast_field(field, value, {:enum, allowed, _mapping}) when is_atom(value) do
    if Enum.member?(allowed, value), do: {:ok, value}, else: {:error, "#{field} is invalid"}
  end

  defp cast_field(field, value, {:enum, _allowed, mapping}) when is_binary(value) do
    case Map.get(mapping, String.downcase(value)) do
      nil -> {:error, "#{field} is invalid"}
      atom -> {:ok, atom}
    end
  end

  defp cast_field(_field, value, :list) when is_list(value), do: {:ok, value}

  defp cast_field(_field, value, :list) when is_binary(value) do
    parsed = String.split(value, ~r/[,\s]+/, trim: true)
    {:ok, parsed}
  end

  defp cast_field(_field, %DateTime{} = value, :datetime), do: {:ok, value}

  defp cast_field(field, value, :datetime) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> {:error, "#{field} is not a valid datetime"}
    end
  end

  defp cast_field(_field, value, :map) when is_map(value), do: {:ok, value}
  defp cast_field(field, _value, :map), do: {:error, "#{field} is not a valid map"}

  defp cast_field(_field, value, nil), do: {:ok, value}

  defp cast_field(field, _value, type) do
    {:error, "#{field} cannot be cast to #{inspect(type)}"}
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?([]), do: true
  defp blank?(_), do: false
end
