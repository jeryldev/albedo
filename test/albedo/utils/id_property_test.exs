defmodule Albedo.Utils.IdPropertyTest do
  use ExUnit.Case, async: true
  use PropCheck

  alias Albedo.Utils.Id

  describe "slugify/1 properties" do
    property "result contains only lowercase alphanumeric and hyphens" do
      forall s <- utf8() do
        result = Id.slugify(s)
        String.match?(result, ~r/^[a-z0-9-]*$/)
      end
    end

    property "result has no leading or trailing hyphens" do
      forall s <- non_empty(utf8()) do
        result = Id.slugify(s)

        result == "" or
          (not String.starts_with?(result, "-") and not String.ends_with?(result, "-"))
      end
    end

    property "result has no consecutive hyphens" do
      forall s <- utf8() do
        result = Id.slugify(s)
        not String.contains?(result, "--")
      end
    end

    property "idempotent - slugifying twice equals slugifying once" do
      forall s <- utf8() do
        once = Id.slugify(s)
        twice = Id.slugify(once)
        once == twice
      end
    end

    property "lowercase input produces same result" do
      forall s <- utf8() do
        Id.slugify(s) == Id.slugify(String.downcase(s))
      end
    end

    property "non-binary input returns empty string" do
      forall input <- oneof([integer(), atom(), list(integer()), nil]) do
        Id.slugify(input) == ""
      end
    end
  end

  describe "parse_numeric_id/1 properties" do
    property "valid numeric string returns the integer" do
      forall n <- pos_integer() do
        Id.parse_numeric_id(%{id: Integer.to_string(n)}) == n
      end
    end

    property "non-numeric string returns 0" do
      forall s <- non_numeric_string() do
        Id.parse_numeric_id(%{id: s}) == 0
      end
    end

    property "missing id field returns 0" do
      forall map <- map_without_id() do
        Id.parse_numeric_id(map) == 0
      end
    end

    property "result is always non-negative" do
      forall input <- oneof([%{id: utf8()}, %{other: integer()}, nil]) do
        Id.parse_numeric_id(input) >= 0
      end
    end
  end

  describe "next_ticket_id/1 properties" do
    property "returns \"1\" for empty list" do
      Id.next_ticket_id([]) == "1"
    end

    property "returns max + 1 for list of tickets" do
      forall tickets <- non_empty(list(ticket_with_numeric_id())) do
        result = Id.next_ticket_id(tickets)
        max_id = tickets |> Enum.map(&Id.parse_numeric_id/1) |> Enum.max()
        result == Integer.to_string(max_id + 1)
      end
    end

    property "result is always a valid positive integer string" do
      forall tickets <- list(ticket_with_numeric_id()) do
        result = Id.next_ticket_id(tickets)
        {n, ""} = Integer.parse(result)
        n > 0
      end
    end
  end

  describe "generate_project_id/2 properties" do
    property "custom name takes precedence" do
      forall {task, custom_name} <- {utf8(), non_empty_string()} do
        result = Id.generate_project_id(task, custom_name)
        result == Id.slugify(String.downcase(custom_name))
      end
    end

    property "generated id contains date prefix" do
      forall task <- non_empty(utf8()) do
        result = Id.generate_project_id(task, nil)
        date = Date.utc_today() |> Date.to_iso8601()
        String.starts_with?(result, date)
      end
    end

    property "generated id has correct format with underscores" do
      forall task <- non_empty(utf8()) do
        result = Id.generate_project_id(task, nil)
        parts = String.split(result, "_")
        length(parts) == 3
      end
    end

    property "suffix is 4 digits" do
      forall task <- non_empty(utf8()) do
        result = Id.generate_project_id(task, nil)
        suffix = result |> String.split("_") |> List.last()
        String.length(suffix) == 4 and String.match?(suffix, ~r/^\d{4}$/)
      end
    end
  end

  defp non_numeric_string do
    such_that(s <- utf8(), when: s != "" and not String.match?(s, ~r/^\d/))
  end

  defp non_empty_string do
    such_that(s <- utf8(), when: s != "" and String.trim(s) != "")
  end

  defp map_without_id do
    let keys <- list(such_that(k <- atom(), when: k != :id)) do
      keys
      |> Enum.map(fn k -> {k, :rand.uniform(100)} end)
      |> Map.new()
    end
  end

  defp ticket_with_numeric_id do
    let n <- pos_integer() do
      %{id: Integer.to_string(n)}
    end
  end
end
