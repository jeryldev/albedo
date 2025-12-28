defmodule Albedo.ChangesetTest do
  use ExUnit.Case, async: true

  alias Albedo.Changeset

  @types %{
    name: :string,
    age: :integer,
    active: :boolean,
    status: {:enum, [:pending, :active, :inactive]},
    priority:
      {:enum, [:low, :medium, :high], %{"low" => :low, "medium" => :medium, "high" => :high}},
    tags: :list,
    created_at: :datetime,
    config: :map
  }

  describe "cast/3" do
    test "casts string values" do
      data = %{name: nil}

      changeset = Changeset.cast({data, @types}, %{name: "Alice"}, [:name])

      assert changeset.valid?
      assert changeset.changes == %{name: "Alice"}
    end

    test "trims string values" do
      data = %{name: nil}

      changeset = Changeset.cast({data, @types}, %{name: "  Alice  "}, [:name])

      assert changeset.changes == %{name: "Alice"}
    end

    test "treats empty strings as nil" do
      data = %{name: nil}

      changeset = Changeset.cast({data, @types}, %{name: ""}, [:name])

      assert changeset.changes == %{}
    end

    test "casts integer values" do
      data = %{age: nil}

      changeset = Changeset.cast({data, @types}, %{age: 25}, [:age])

      assert changeset.changes == %{age: 25}
    end

    test "casts string to integer" do
      data = %{age: nil}

      changeset = Changeset.cast({data, @types}, %{age: "25"}, [:age])

      assert changeset.changes == %{age: 25}
    end

    test "returns error for invalid integer" do
      data = %{age: nil}

      changeset = Changeset.cast({data, @types}, %{age: "abc"}, [:age])

      assert not changeset.valid?
      assert {:age, {"age is not a valid integer", []}} in changeset.errors
    end

    test "casts boolean values" do
      data = %{active: nil}

      changeset = Changeset.cast({data, @types}, %{active: true}, [:active])

      assert changeset.changes == %{active: true}
    end

    test "casts string to boolean" do
      data = %{active: nil}

      true_changeset = Changeset.cast({data, @types}, %{active: "true"}, [:active])
      assert true_changeset.changes == %{active: true}

      false_changeset = Changeset.cast({data, @types}, %{active: "false"}, [:active])
      assert false_changeset.changes == %{active: false}
    end

    test "casts enum values (atom)" do
      data = %{status: nil}

      changeset = Changeset.cast({data, @types}, %{status: :active}, [:status])

      assert changeset.changes == %{status: :active}
    end

    test "casts enum values (string)" do
      data = %{status: nil}

      changeset = Changeset.cast({data, @types}, %{status: "pending"}, [:status])

      assert changeset.changes == %{status: :pending}
    end

    test "returns error for invalid enum" do
      data = %{status: nil}

      changeset = Changeset.cast({data, @types}, %{status: "invalid"}, [:status])

      assert not changeset.valid?
      assert {:status, {"status is invalid", []}} in changeset.errors
    end

    test "casts enum with mapping" do
      data = %{priority: nil}

      changeset = Changeset.cast({data, @types}, %{priority: "high"}, [:priority])

      assert changeset.changes == %{priority: :high}
    end

    test "casts list values" do
      data = %{tags: nil}

      changeset = Changeset.cast({data, @types}, %{tags: ["a", "b"]}, [:tags])

      assert changeset.changes == %{tags: ["a", "b"]}
    end

    test "parses comma-separated string to list" do
      data = %{tags: nil}

      changeset = Changeset.cast({data, @types}, %{tags: "a,b,c"}, [:tags])

      assert changeset.changes == %{tags: ["a", "b", "c"]}
    end

    test "casts datetime values" do
      data = %{created_at: nil}
      now = DateTime.utc_now()

      changeset = Changeset.cast({data, @types}, %{created_at: now}, [:created_at])

      assert changeset.changes == %{created_at: now}
    end

    test "parses ISO8601 string to datetime" do
      data = %{created_at: nil}

      changeset =
        Changeset.cast({data, @types}, %{created_at: "2024-01-15T10:30:00Z"}, [:created_at])

      assert %DateTime{} = changeset.changes.created_at
    end

    test "casts map values" do
      data = %{config: nil}

      changeset = Changeset.cast({data, @types}, %{config: %{key: "value"}}, [:config])

      assert changeset.changes == %{config: %{key: "value"}}
    end

    test "handles string keys in params" do
      data = %{name: nil}

      changeset = Changeset.cast({data, @types}, %{"name" => "Alice"}, [:name])

      assert changeset.changes == %{name: "Alice"}
    end

    test "ignores non-permitted fields" do
      data = %{name: nil, age: nil}

      changeset = Changeset.cast({data, @types}, %{name: "Alice", age: 25}, [:name])

      assert changeset.changes == %{name: "Alice"}
    end
  end

  describe "validate_required/2" do
    test "passes when required field is present" do
      changeset =
        Changeset.cast({%{name: nil}, @types}, %{name: "Alice"}, [:name])
        |> Changeset.validate_required([:name])

      assert changeset.valid?
    end

    test "fails when required field is missing" do
      changeset =
        Changeset.cast({%{name: nil}, @types}, %{}, [:name])
        |> Changeset.validate_required([:name])

      assert not changeset.valid?
      assert {:name, {"can't be blank", []}} in changeset.errors
    end

    test "fails when required field is empty string" do
      changeset =
        Changeset.cast({%{name: nil}, @types}, %{name: ""}, [:name])
        |> Changeset.validate_required([:name])

      assert not changeset.valid?
    end

    test "fails when required field is empty list" do
      changeset =
        Changeset.cast({%{tags: nil}, @types}, %{tags: []}, [:tags])
        |> Changeset.validate_required([:tags])

      assert not changeset.valid?
    end
  end

  describe "get_field/2" do
    test "returns changed value when field is changed" do
      changeset = Changeset.cast({%{name: "Original"}, @types}, %{name: "Updated"}, [:name])

      assert Changeset.get_field(changeset, :name) == "Updated"
    end

    test "returns data value when field is not changed" do
      changeset = Changeset.cast({%{name: "Original"}, @types}, %{}, [:name])

      assert Changeset.get_field(changeset, :name) == "Original"
    end
  end

  describe "get_change/2" do
    test "returns change when field is changed" do
      changeset = Changeset.cast({%{name: nil}, @types}, %{name: "Alice"}, [:name])

      assert Changeset.get_change(changeset, :name) == "Alice"
    end

    test "returns nil when field is not changed" do
      changeset = Changeset.cast({%{name: nil}, @types}, %{}, [:name])

      assert Changeset.get_change(changeset, :name) == nil
    end

    test "returns default when field is not changed" do
      changeset = Changeset.cast({%{name: nil}, @types}, %{}, [:name])

      assert Changeset.get_change(changeset, :name, "default") == "default"
    end
  end

  describe "put_change/3" do
    test "adds change to changeset" do
      changeset =
        Changeset.cast({%{name: nil}, @types}, %{}, [:name])
        |> Changeset.put_change(:name, "Alice")

      assert changeset.changes == %{name: "Alice"}
    end
  end

  describe "add_error/3" do
    test "adds error to changeset" do
      changeset =
        Changeset.cast({%{name: nil}, @types}, %{name: "Alice"}, [:name])
        |> Changeset.add_error(:name, "is invalid")

      assert not changeset.valid?
      assert {:name, {"is invalid", []}} in changeset.errors
    end
  end

  describe "apply_changes/1" do
    test "merges changes into data" do
      changeset =
        Changeset.cast({%{name: "Original", age: 20}, @types}, %{name: "Updated"}, [:name])

      result = Changeset.apply_changes(changeset)

      assert result == %{name: "Updated", age: 20}
    end
  end

  describe "apply_action/2" do
    test "returns {:ok, data} when valid" do
      changeset =
        Changeset.cast({%{name: nil}, @types}, %{name: "Alice"}, [:name])
        |> Changeset.validate_required([:name])

      assert {:ok, %{name: "Alice"}} = Changeset.apply_action(changeset, :insert)
    end

    test "returns {:error, changeset} when invalid" do
      changeset =
        Changeset.cast({%{name: nil}, @types}, %{}, [:name])
        |> Changeset.validate_required([:name])

      assert {:error, %Changeset{valid?: false}} = Changeset.apply_action(changeset, :insert)
    end
  end
end
