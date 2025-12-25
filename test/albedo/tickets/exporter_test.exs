defmodule Albedo.Tickets.ExporterTest do
  use ExUnit.Case, async: true

  alias Albedo.Tickets
  alias Albedo.Tickets.Exporter
  alias Albedo.Tickets.Ticket

  @test_data Tickets.new("test-session", "Build user authentication", [
               Ticket.new(%{
                 id: "1",
                 title: "Create User schema",
                 description: "Create the User schema with email and password fields",
                 type: "task",
                 priority: "high",
                 estimate: 3,
                 labels: ["backend", "database"],
                 acceptance_criteria: ["User schema exists", "Tests pass"],
                 files: %{create: ["lib/app/user.ex"], modify: ["lib/app/accounts.ex"]},
                 dependencies: %{blocked_by: [], blocks: ["2"]}
               }),
               %{
                 Ticket.new(%{
                   id: "2",
                   title: "Add login form",
                   description: "Create the login LiveView",
                   type: "story",
                   priority: "medium",
                   estimate: 5,
                   labels: ["frontend", "liveview"],
                   acceptance_criteria: ["Form displays", "Validation works"],
                   files: %{create: ["lib/app_web/live/login_live.ex"], modify: []},
                   dependencies: %{blocked_by: ["1"], blocks: []}
                 })
                 | status: :in_progress
               },
               %{
                 Ticket.new(%{
                   id: "3",
                   title: "Add tests",
                   type: "test",
                   priority: "low",
                   estimate: 2
                 })
                 | status: :completed
               }
             ])

  describe "formats/0" do
    test "returns list of available formats" do
      formats = Exporter.formats()
      assert :json in formats
      assert :csv in formats
      assert :markdown in formats
      assert :github in formats
    end
  end

  describe "export/3" do
    test "returns error for unknown format" do
      assert {:error, {:unknown_format, :unknown}} = Exporter.export(@test_data, :unknown)
    end
  end

  describe "JSON exporter" do
    test "exports valid JSON" do
      {:ok, content} = Exporter.export(@test_data, :json)
      assert {:ok, parsed} = Jason.decode(content)

      assert parsed["session_id"] == "test-session"
      assert parsed["task_description"] == "Build user authentication"
      assert length(parsed["tickets"]) == 3
    end

    test "includes summary" do
      {:ok, content} = Exporter.export(@test_data, :json)
      {:ok, parsed} = Jason.decode(content)

      assert parsed["summary"]["total"] == 3
      assert parsed["summary"]["pending"] == 1
      assert parsed["summary"]["in_progress"] == 1
      assert parsed["summary"]["completed"] == 1
    end

    test "filters by status" do
      {:ok, content} = Exporter.export(@test_data, :json, status: :pending)
      {:ok, parsed} = Jason.decode(content)

      assert length(parsed["tickets"]) == 1
      assert hd(parsed["tickets"])["status"] == "pending"
    end

    test "has correct file extension" do
      assert Exporter.file_extension(:json) == ".json"
    end
  end

  describe "CSV exporter" do
    test "exports valid CSV with headers" do
      {:ok, content} = Exporter.export(@test_data, :csv)
      lines = String.split(content, "\n")

      assert hd(lines) =~ "id,title,type,status,priority"
      assert length(lines) == 4
    end

    test "escapes fields with commas" do
      data =
        Tickets.new("test", "task", [
          Ticket.new(%{id: "1", title: "Title, with comma", description: "Desc"})
        ])

      {:ok, content} = Exporter.export(data, :csv)
      assert content =~ "\"Title, with comma\""
    end

    test "escapes fields with quotes" do
      data =
        Tickets.new("test", "task", [
          Ticket.new(%{id: "1", title: "Title with \"quotes\"", description: "Desc"})
        ])

      {:ok, content} = Exporter.export(data, :csv)
      assert content =~ "\"Title with \"\"quotes\"\"\""
    end

    test "filters by status" do
      {:ok, content} = Exporter.export(@test_data, :csv, status: :completed)
      lines = String.split(content, "\n")

      assert length(lines) == 2
    end

    test "has correct file extension" do
      assert Exporter.file_extension(:csv) == ".csv"
    end
  end

  describe "Markdown exporter" do
    test "exports valid markdown" do
      {:ok, content} = Exporter.export(@test_data, :markdown)

      assert content =~ "# Build user authentication"
      assert content =~ "**Session:** test-session"
      assert content =~ "## Summary"
      assert content =~ "## Tickets"
    end

    test "includes ticket details" do
      {:ok, content} = Exporter.export(@test_data, :markdown)

      assert content =~ "Create User schema"
      assert content =~ "**Labels:**"
      assert content =~ "`backend`"
      assert content =~ "**Acceptance Criteria:**"
      assert content =~ "- [ ] User schema exists"
    end

    test "shows status checkboxes" do
      {:ok, content} = Exporter.export(@test_data, :markdown)

      assert content =~ "[ ]"
      assert content =~ "[~]"
      assert content =~ "[x]"
    end

    test "includes priority badges" do
      {:ok, content} = Exporter.export(@test_data, :markdown)

      assert content =~ "🟠"
      assert content =~ "🟡"
      assert content =~ "🟢"
    end

    test "filters by status" do
      {:ok, content} = Exporter.export(@test_data, :markdown, status: :pending)
      refute content =~ "Add login form"
      assert content =~ "Create User schema"
    end

    test "has correct file extension" do
      assert Exporter.file_extension(:markdown) == ".md"
    end
  end

  describe "GitHub exporter" do
    test "exports valid JSON with issues" do
      {:ok, content} = Exporter.export(@test_data, :github)
      {:ok, parsed} = Jason.decode(content)

      assert parsed["source"] == "albedo"
      assert parsed["session_id"] == "test-session"
      assert length(parsed["issues"]) == 3
    end

    test "formats issues correctly" do
      {:ok, content} = Exporter.export(@test_data, :github)
      {:ok, parsed} = Jason.decode(content)

      [issue | _] = parsed["issues"]

      assert issue["title"] == "Create User schema"
      assert is_binary(issue["body"])
      assert is_list(issue["labels"])
      assert issue["state"] in ["open", "closed"]
    end

    test "includes type and priority labels" do
      {:ok, content} = Exporter.export(@test_data, :github)
      {:ok, parsed} = Jason.decode(content)

      [issue | _] = parsed["issues"]

      assert "type:feature" in issue["labels"]
      assert "priority:high" in issue["labels"]
      assert "estimate:3" in issue["labels"]
    end

    test "sets state based on ticket status" do
      {:ok, content} = Exporter.export(@test_data, :github)
      {:ok, parsed} = Jason.decode(content)

      issues_by_title = Enum.group_by(parsed["issues"], & &1["title"])

      assert hd(issues_by_title["Create User schema"])["state"] == "open"
      assert hd(issues_by_title["Add tests"])["state"] == "closed"
    end

    test "includes acceptance criteria as checkboxes" do
      {:ok, content} = Exporter.export(@test_data, :github)
      {:ok, parsed} = Jason.decode(content)

      [issue | _] = parsed["issues"]

      assert issue["body"] =~ "## Acceptance Criteria"
      assert issue["body"] =~ "- [ ] User schema exists"
    end

    test "has correct file extension" do
      assert Exporter.file_extension(:github) == ".github.json"
    end
  end

  describe "default_filename/2" do
    test "generates filename with correct extension" do
      assert Exporter.default_filename("my-session", :json) == "my-session_tickets.json"
      assert Exporter.default_filename("my-session", :csv) == "my-session_tickets.csv"
      assert Exporter.default_filename("my-session", :markdown) == "my-session_tickets.md"
      assert Exporter.default_filename("my-session", :github) == "my-session_tickets.github.json"
    end
  end

  describe "format_name/1" do
    test "returns human-readable format names" do
      assert Exporter.format_name(:json) == "JSON"
      assert Exporter.format_name(:csv) == "CSV"
      assert Exporter.format_name(:markdown) == "Markdown"
      assert Exporter.format_name(:github) == "GitHub Issues"
    end
  end
end
