defmodule Albedo.Tickets.ParserTest do
  use ExUnit.Case, async: true

  alias Albedo.Tickets.Parser

  @sample_json """
  {
    "summary": {
      "title": "User Authentication",
      "description": "Add user authentication to the application.",
      "domain_context": ["Security best practices", "OAuth standards"],
      "in_scope": ["Login form", "User schema"],
      "out_of_scope": ["Social login"],
      "assumptions": ["PostgreSQL database"]
    },
    "tickets": [
      {
        "id": "1",
        "title": "Create User schema",
        "description": "Create the User schema with email and password fields.",
        "type": "feature",
        "priority": "high",
        "estimate": "medium",
        "labels": ["backend", "database"],
        "acceptance_criteria": [
          "User schema exists with email field",
          "Password is properly hashed",
          "Tests pass"
        ],
        "implementation_notes": "Use Argon2 for password hashing.",
        "files": {
          "create": ["lib/my_app/accounts/user.ex", "priv/repo/migrations/create_users.exs"],
          "modify": ["lib/my_app/accounts.ex"]
        },
        "dependencies": {
          "blocked_by": [],
          "blocks": ["2", "3"]
        }
      },
      {
        "id": "2",
        "title": "Add login form",
        "description": "Create the login LiveView form.",
        "type": "feature",
        "priority": "medium",
        "estimate": "small",
        "labels": ["liveview", "frontend"],
        "acceptance_criteria": ["Login form displays", "Validation works"],
        "files": {
          "create": ["lib/my_app_web/live/login_live.ex"],
          "modify": []
        },
        "dependencies": {
          "blocked_by": ["1"],
          "blocks": []
        }
      }
    ],
    "implementation_order": [
      {"ticket_id": "1", "reason": "Foundation for authentication"},
      {"ticket_id": "2", "reason": "Depends on User schema"}
    ],
    "risks": [
      {"risk": "Security vulnerabilities", "likelihood": "medium", "impact": "high", "mitigation": "Code review"}
    ],
    "effort_summary": {
      "total_tickets": 2,
      "total_points": 5
    }
  }
  """

  @sample_json_array """
  [
    {
      "id": "1",
      "title": "Simple task",
      "type": "feature",
      "priority": "medium",
      "estimate": "small"
    }
  ]
  """

  @sample_markdown """
  # Feature: User Authentication

  ## Executive Summary
  Add user authentication to the application.

  ## Tickets

  ### Ticket #1: Create User schema

  **Type:** Task
  **Priority:** High
  **Estimate:** Medium
  **Depends On:** None
  **Blocks:** #2, #3

  #### Description
  Create the User schema with email and password fields.

  #### Implementation Notes
  Use Argon2 for password hashing.

  #### Files to Create
  | File | Purpose |
  |------|---------|
  | lib/my_app/accounts/user.ex | User schema |
  | priv/repo/migrations/create_users.exs | Migration |

  #### Files to Modify
  | File | Changes |
  |------|---------|
  | lib/my_app/accounts.ex | Add user functions |

  #### Acceptance Criteria
  - [ ] User schema exists with email field
  - [ ] Password is properly hashed
  - [ ] Tests pass

  ---

  ### Ticket #2: Add login form

  **Type:** Story
  **Priority:** Medium
  **Estimate:** Small
  **Depends On:** #1
  **Blocks:** None

  #### Description
  Create the login LiveView form.

  #### Files to Create
  | File | Purpose |
  |------|---------|
  | lib/my_app_web/live/login_live.ex | Login LiveView |

  #### Acceptance Criteria
  - [ ] Login form displays
  - [ ] Validation works

  ---

  ## Dependency Graph
  ```mermaid
  graph LR
      T1 --> T2
  ```
  """

  describe "parse/1" do
    test "parses tickets from markdown" do
      {:ok, tickets} = Parser.parse(@sample_markdown)

      assert length(tickets) == 2

      [ticket1, ticket2] = tickets

      assert ticket1.id == "1"
      assert ticket1.title == "Create User schema"
      assert ticket1.type == :feature
      assert ticket1.priority == :high
      assert ticket1.estimate == 3
      assert ticket1.status == :pending
      assert ticket1.dependencies.blocks == ["2", "3"]

      assert ticket2.id == "2"
      assert ticket2.title == "Add login form"
      assert ticket2.priority == :medium
      assert ticket2.estimate == 2
      assert ticket2.dependencies.blocked_by == ["1"]
    end

    test "extracts files to create" do
      {:ok, [ticket | _]} = Parser.parse(@sample_markdown)

      assert "lib/my_app/accounts/user.ex" in ticket.files.create
      assert "priv/repo/migrations/create_users.exs" in ticket.files.create
    end

    test "extracts files to modify" do
      {:ok, [ticket | _]} = Parser.parse(@sample_markdown)

      assert "lib/my_app/accounts.ex" in ticket.files.modify
    end

    test "extracts acceptance criteria" do
      {:ok, [ticket | _]} = Parser.parse(@sample_markdown)

      assert "User schema exists with email field" in ticket.acceptance_criteria
      assert "Password is properly hashed" in ticket.acceptance_criteria
      assert "Tests pass" in ticket.acceptance_criteria
    end

    test "infers labels from file paths" do
      {:ok, [ticket | _]} = Parser.parse(@sample_markdown)

      assert "backend" in ticket.labels
      assert "database" in ticket.labels
    end

    test "returns error for invalid content" do
      assert {:error, :invalid_content} = Parser.parse(nil)
      assert {:error, :invalid_content} = Parser.parse(123)
    end

    test "returns empty list for markdown without tickets" do
      {:ok, tickets} = Parser.parse("# Just a header\n\nSome text")
      assert tickets == []
    end
  end

  describe "parse/1 with different ticket formats" do
    test "handles tickets without dependencies" do
      markdown = """
      ### Ticket #1: Simple Task

      **Type:** Task
      **Priority:** Low
      **Estimate:** Small
      **Depends On:** None
      **Blocks:** None

      #### Description
      A simple task.

      #### Acceptance Criteria
      - [ ] Task complete
      """

      {:ok, [ticket]} = Parser.parse(markdown)

      assert ticket.dependencies.blocked_by == []
      assert ticket.dependencies.blocks == []
    end

    test "handles different checkbox formats" do
      markdown = """
      ### Ticket #1: Test

      **Type:** Task
      **Priority:** Medium
      **Estimate:** Small

      #### Acceptance Criteria
      - [ ] Unchecked item
      - [x] Checked item
      - Item without checkbox
      """

      {:ok, [ticket]} = Parser.parse(markdown)

      assert "Unchecked item" in ticket.acceptance_criteria
      assert "Checked item" in ticket.acceptance_criteria
      assert "Item without checkbox" in ticket.acceptance_criteria
    end

    test "handles bug type" do
      markdown = """
      ### Ticket #1: Fix login issue

      **Type:** Bug
      **Priority:** Urgent
      **Estimate:** Large

      #### Description
      Users cannot log in.
      """

      {:ok, [ticket]} = Parser.parse(markdown)

      assert ticket.type == :bugfix
      assert ticket.priority == :urgent
      assert ticket.estimate == 5
    end
  end

  describe "parse/1 with JSON format" do
    test "parses tickets from structured JSON" do
      {:ok, tickets} = Parser.parse(@sample_json)

      assert length(tickets) == 2

      [ticket1, ticket2] = tickets

      assert ticket1.id == "1"
      assert ticket1.title == "Create User schema"
      assert ticket1.type == :feature
      assert ticket1.priority == :high
      assert ticket1.estimate == 3
      assert ticket1.status == :pending
      assert ticket1.dependencies.blocks == ["2", "3"]

      assert ticket2.id == "2"
      assert ticket2.title == "Add login form"
      assert ticket2.priority == :medium
      assert ticket2.estimate == 2
      assert ticket2.dependencies.blocked_by == ["1"]
    end

    test "parses JSON array directly" do
      {:ok, [ticket]} = Parser.parse(@sample_json_array)

      assert ticket.id == "1"
      assert ticket.title == "Simple task"
      assert ticket.type == :feature
      assert ticket.estimate == 2
    end

    test "extracts files from JSON" do
      {:ok, [ticket | _]} = Parser.parse(@sample_json)

      assert "lib/my_app/accounts/user.ex" in ticket.files.create
      assert "priv/repo/migrations/create_users.exs" in ticket.files.create
      assert "lib/my_app/accounts.ex" in ticket.files.modify
    end

    test "extracts acceptance criteria from JSON" do
      {:ok, [ticket | _]} = Parser.parse(@sample_json)

      assert "User schema exists with email field" in ticket.acceptance_criteria
      assert "Password is properly hashed" in ticket.acceptance_criteria
      assert "Tests pass" in ticket.acceptance_criteria
    end

    test "extracts labels from JSON" do
      {:ok, [ticket | _]} = Parser.parse(@sample_json)

      assert "backend" in ticket.labels
      assert "database" in ticket.labels
    end

    test "handles JSON wrapped in code block" do
      json_with_block = """
      ```json
      {
        "tickets": [
          {"id": "1", "title": "Test", "type": "feature", "priority": "medium"}
        ]
      }
      ```
      """

      {:ok, [ticket]} = Parser.parse(json_with_block)

      assert ticket.id == "1"
      assert ticket.title == "Test"
    end

    test "handles missing optional fields in JSON" do
      json = """
      {"tickets": [{"id": "1", "title": "Minimal", "type": "feature", "priority": "medium"}]}
      """

      {:ok, [ticket]} = Parser.parse(json)

      assert ticket.id == "1"
      assert ticket.title == "Minimal"
      assert ticket.estimate == nil
      assert ticket.labels == []
      assert ticket.files.create == []
      assert ticket.files.modify == []
      assert ticket.dependencies.blocked_by == []
    end
  end

  describe "parse_json/1" do
    test "parses JSON directly" do
      {:ok, tickets} = Parser.parse_json(@sample_json)
      assert length(tickets) == 2
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_parse_error, _}} = Parser.parse_json("not json")
    end

    test "returns error for missing tickets array" do
      assert {:error, :missing_tickets_array} = Parser.parse_json("{\"data\": 123}")
    end
  end

  describe "parse_structured_response/1" do
    test "parses full structured response with summary" do
      {:ok, response} = Parser.parse_structured_response(@sample_json)

      assert response.summary.title == "User Authentication"
      assert response.summary.description == "Add user authentication to the application."
      assert "Security best practices" in response.summary.domain_context
      assert "Login form" in response.summary.in_scope
      assert "Social login" in response.summary.out_of_scope

      assert length(response.tickets) == 2
      assert length(response.risks) == 1
      assert length(response.implementation_order) == 2
    end

    test "calculates effort summary from tickets" do
      {:ok, response} = Parser.parse_structured_response(@sample_json_array)

      assert response.effort_summary.total_tickets == 1
      assert response.effort_summary.total_points == 2
    end

    test "handles response without summary" do
      {:ok, response} = Parser.parse_structured_response(@sample_json_array)

      assert response.summary == nil
      assert length(response.tickets) == 1
    end
  end

  describe "parse/1 format detection" do
    test "auto-detects JSON format" do
      {:ok, tickets} = Parser.parse(@sample_json)
      assert length(tickets) == 2
    end

    test "auto-detects markdown format" do
      {:ok, tickets} = Parser.parse(@sample_markdown)
      assert length(tickets) == 2
    end

    test "returns error for unrecognized format" do
      result = Parser.parse("Just some random text without tickets")
      assert {:error, :unrecognized_format} = result
    end
  end
end
