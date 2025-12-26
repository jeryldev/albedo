defmodule Albedo.Tickets.SchemaTest do
  use ExUnit.Case, async: true

  alias Albedo.Tickets.Schema

  describe "ticket_schema/0" do
    test "returns valid JSON schema for ticket" do
      schema = Schema.ticket_schema()

      assert schema["type"] == "object"
      assert "id" in schema["required"]
      assert "title" in schema["required"]
      assert "type" in schema["required"]
      assert "priority" in schema["required"]

      properties = schema["properties"]
      assert properties["id"]["type"] == "string"
      assert properties["title"]["type"] == "string"
      assert properties["type"]["enum"] == Schema.ticket_types()
      assert properties["priority"]["enum"] == Schema.priorities()
    end

    test "includes file properties" do
      schema = Schema.ticket_schema()
      files = schema["properties"]["files"]

      assert files["type"] == "object"
      assert files["properties"]["create"]["type"] == "array"
      assert files["properties"]["modify"]["type"] == "array"
    end

    test "includes dependency properties" do
      schema = Schema.ticket_schema()
      deps = schema["properties"]["dependencies"]

      assert deps["type"] == "object"
      assert deps["properties"]["blocked_by"]["type"] == "array"
      assert deps["properties"]["blocks"]["type"] == "array"
    end
  end

  describe "planning_response_schema/0" do
    test "returns valid JSON schema for planning response" do
      schema = Schema.planning_response_schema()

      assert schema["type"] == "object"
      assert "summary" in schema["required"]
      assert "tickets" in schema["required"]

      tickets = schema["properties"]["tickets"]
      assert tickets["type"] == "array"
    end

    test "includes summary properties" do
      schema = Schema.planning_response_schema()
      summary = schema["properties"]["summary"]

      assert summary["type"] == "object"
      assert "title" in summary["required"]
      assert "description" in summary["required"]
    end

    test "includes risks properties" do
      schema = Schema.planning_response_schema()
      risks = schema["properties"]["risks"]

      assert risks["type"] == "array"
      risk_item = risks["items"]
      assert risk_item["properties"]["risk"]["type"] == "string"
      assert risk_item["properties"]["likelihood"]["enum"] == ["low", "medium", "high"]
    end
  end

  describe "schema_as_string/0" do
    test "returns valid JSON string" do
      json_string = Schema.schema_as_string()

      assert is_binary(json_string)
      assert {:ok, _} = Jason.decode(json_string)
    end
  end

  describe "ticket_types/0" do
    test "returns list of ticket types" do
      types = Schema.ticket_types()

      assert "feature" in types
      assert "enhancement" in types
      assert "bugfix" in types
      assert "chore" in types
      assert "docs" in types
      assert "test" in types
    end
  end

  describe "priorities/0" do
    test "returns list of priorities" do
      priorities = Schema.priorities()

      assert "urgent" in priorities
      assert "high" in priorities
      assert "medium" in priorities
      assert "low" in priorities
      assert "none" in priorities
    end
  end

  describe "estimate_mapping/0" do
    test "returns mapping of estimate names to points" do
      mapping = Schema.estimate_mapping()

      assert mapping["trivial"] == 1
      assert mapping["small"] == 2
      assert mapping["medium"] == 3
      assert mapping["large"] == 5
      assert mapping["extra large"] == 8
      assert mapping["epic"] == 13
    end
  end
end
