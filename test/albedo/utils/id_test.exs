defmodule Albedo.Utils.IdTest do
  use ExUnit.Case, async: true

  alias Albedo.Utils.Id

  describe "generate_project_id/2" do
    test "returns custom name when provided" do
      assert Id.generate_project_id("Some Task", "my-custom-name") == "my-custom-name"
    end

    test "slugifies custom name" do
      assert Id.generate_project_id("Task", "My Custom Project") == "my-custom-project"
    end

    test "generates date-based ID when no custom name" do
      result = Id.generate_project_id("Add user authentication")
      today = Date.utc_today() |> Date.to_iso8601()

      assert String.starts_with?(result, today)
      assert result =~ ~r/^\d{4}-\d{2}-\d{2}_add-user-authentication_\d{4}$/
    end

    test "truncates long task descriptions to 30 chars" do
      long_task = "This is a very long task description that exceeds thirty characters"
      result = Id.generate_project_id(long_task)

      slug_part = result |> String.split("_") |> Enum.at(1)
      assert String.length(slug_part) <= 30
    end

    test "generates unique suffix" do
      id1 = Id.generate_project_id("Test task")
      id2 = Id.generate_project_id("Test task")

      assert id1 != id2
    end

    test "handles nil custom name" do
      result = Id.generate_project_id("Test task", nil)
      today = Date.utc_today() |> Date.to_iso8601()

      assert String.starts_with?(result, today)
    end

    test "handles empty string custom name" do
      result = Id.generate_project_id("Test task", "")
      today = Date.utc_today() |> Date.to_iso8601()

      assert String.starts_with?(result, today)
    end
  end

  describe "next_ticket_id/1" do
    test "returns '1' for empty list" do
      assert Id.next_ticket_id([]) == "1"
    end

    test "returns next sequential ID" do
      tickets = [%{id: "1"}, %{id: "2"}, %{id: "3"}]
      assert Id.next_ticket_id(tickets) == "4"
    end

    test "finds maximum and adds one" do
      tickets = [%{id: "5"}, %{id: "2"}, %{id: "10"}]
      assert Id.next_ticket_id(tickets) == "11"
    end

    test "handles non-numeric IDs" do
      tickets = [%{id: "abc"}, %{id: "2"}, %{id: "xyz"}]
      assert Id.next_ticket_id(tickets) == "3"
    end

    test "handles mixed valid and invalid IDs" do
      tickets = [%{id: "1"}, %{id: "invalid"}, %{id: "5"}, %{id: nil}]
      assert Id.next_ticket_id(tickets) == "6"
    end
  end

  describe "parse_numeric_id/1" do
    test "parses valid numeric string ID" do
      assert Id.parse_numeric_id(%{id: "5"}) == 5
    end

    test "parses string with trailing content" do
      assert Id.parse_numeric_id(%{id: "123abc"}) == 123
    end

    test "returns 0 for non-numeric ID" do
      assert Id.parse_numeric_id(%{id: "abc"}) == 0
    end

    test "returns 0 for nil ID" do
      assert Id.parse_numeric_id(%{id: nil}) == 0
    end

    test "returns 0 for non-map input" do
      assert Id.parse_numeric_id("not a map") == 0
      assert Id.parse_numeric_id(123) == 0
      assert Id.parse_numeric_id(nil) == 0
    end

    test "returns 0 for map without id key" do
      assert Id.parse_numeric_id(%{name: "test"}) == 0
    end
  end

  describe "generate_unique_project_id/2" do
    test "slugifies the name" do
      assert Id.generate_unique_project_id("My Project", []) == "my-project"
    end

    test "replaces spaces with hyphens" do
      assert Id.generate_unique_project_id("Hello World Test", []) == "hello-world-test"
    end

    test "returns base name when no duplicates exist" do
      existing = ["other-project", "another-one"]
      assert Id.generate_unique_project_id("My Project", existing) == "my-project"
    end

    test "appends -1 when duplicate exists" do
      existing = ["my-project"]
      assert Id.generate_unique_project_id("My Project", existing) == "my-project-1"
    end

    test "appends -2 when -1 also exists" do
      existing = ["my-project", "my-project-1"]
      assert Id.generate_unique_project_id("My Project", existing) == "my-project-2"
    end

    test "finds next available number in sequence" do
      existing = ["my-project", "my-project-1", "my-project-2", "my-project-3"]
      assert Id.generate_unique_project_id("My Project", existing) == "my-project-4"
    end

    test "handles gaps in sequence" do
      existing = ["my-project", "my-project-2", "my-project-5"]
      assert Id.generate_unique_project_id("My Project", existing) == "my-project-1"
    end

    test "handles special characters in name" do
      assert Id.generate_unique_project_id("Test! Project @#$", []) == "test-project"
    end

    test "handles empty existing list" do
      assert Id.generate_unique_project_id("New Project", []) == "new-project"
    end
  end

  describe "slugify/1" do
    test "converts to lowercase" do
      assert Id.slugify("Hello World") == "hello-world"
    end

    test "replaces non-alphanumeric with hyphens" do
      assert Id.slugify("Hello! World?") == "hello-world"
    end

    test "trims leading and trailing hyphens" do
      assert Id.slugify("!Hello World!") == "hello-world"
    end

    test "replaces multiple special chars with single hyphen" do
      assert Id.slugify("Hello   World") == "hello-world"
      assert Id.slugify("Hello---World") == "hello-world"
    end

    test "handles already lowercase string" do
      assert Id.slugify("hello-world") == "hello-world"
    end

    test "returns empty string for non-binary input" do
      assert Id.slugify(nil) == ""
      assert Id.slugify(123) == ""
    end

    test "handles empty string" do
      assert Id.slugify("") == ""
    end

    test "preserves numbers" do
      assert Id.slugify("Test 123 Task") == "test-123-task"
    end
  end
end
