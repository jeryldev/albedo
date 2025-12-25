defmodule Albedo.Tickets.ParserTest do
  use ExUnit.Case, async: true

  alias Albedo.Tickets.Parser

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
  | lib/my_app_web/live/session_live.ex | Login LiveView |

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
end
