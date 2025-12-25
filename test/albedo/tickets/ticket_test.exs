defmodule Albedo.Tickets.TicketTest do
  use ExUnit.Case, async: true

  alias Albedo.Tickets.Ticket

  describe "new/1" do
    test "creates ticket with required fields" do
      ticket = Ticket.new(%{id: "1", title: "Test ticket"})

      assert ticket.id == "1"
      assert ticket.title == "Test ticket"
      assert ticket.status == :pending
      assert ticket.type == :feature
      assert ticket.priority == :medium
    end

    test "creates ticket with all fields" do
      ticket =
        Ticket.new(%{
          id: "1",
          title: "Test ticket",
          description: "A test description",
          type: "bugfix",
          priority: "high",
          estimate: "medium",
          labels: ["backend", "database"],
          acceptance_criteria: ["Criterion 1", "Criterion 2"],
          implementation_notes: "Some notes",
          files: %{create: ["lib/test.ex"], modify: ["lib/existing.ex"]},
          dependencies: %{blocked_by: ["2"], blocks: ["3", "4"]}
        })

      assert ticket.id == "1"
      assert ticket.title == "Test ticket"
      assert ticket.description == "A test description"
      assert ticket.type == :bugfix
      assert ticket.priority == :high
      assert ticket.estimate == 3
      assert ticket.labels == ["backend", "database"]
      assert ticket.acceptance_criteria == ["Criterion 1", "Criterion 2"]
      assert ticket.implementation_notes == "Some notes"
      assert ticket.files.create == ["lib/test.ex"]
      assert ticket.files.modify == ["lib/existing.ex"]
      assert ticket.dependencies.blocked_by == ["2"]
      assert ticket.dependencies.blocks == ["3", "4"]
    end

    test "parses estimate strings to points" do
      assert Ticket.new(%{id: "1", title: "T", estimate: "trivial"}).estimate == 1
      assert Ticket.new(%{id: "1", title: "T", estimate: "small"}).estimate == 2
      assert Ticket.new(%{id: "1", title: "T", estimate: "medium"}).estimate == 3
      assert Ticket.new(%{id: "1", title: "T", estimate: "large"}).estimate == 5
      assert Ticket.new(%{id: "1", title: "T", estimate: "extra large"}).estimate == 8
      assert Ticket.new(%{id: "1", title: "T", estimate: "epic"}).estimate == 13
    end

    test "parses type strings" do
      assert Ticket.new(%{id: "1", title: "T", type: "task"}).type == :feature
      assert Ticket.new(%{id: "1", title: "T", type: "story"}).type == :feature
      assert Ticket.new(%{id: "1", title: "T", type: "bug"}).type == :bugfix
      assert Ticket.new(%{id: "1", title: "T", type: "chore"}).type == :chore
      assert Ticket.new(%{id: "1", title: "T", type: "docs"}).type == :docs
      assert Ticket.new(%{id: "1", title: "T", type: "test"}).type == :test
    end

    test "parses priority strings" do
      assert Ticket.new(%{id: "1", title: "T", priority: "urgent"}).priority == :urgent
      assert Ticket.new(%{id: "1", title: "T", priority: "high"}).priority == :high
      assert Ticket.new(%{id: "1", title: "T", priority: "medium"}).priority == :medium
      assert Ticket.new(%{id: "1", title: "T", priority: "low"}).priority == :low
      assert Ticket.new(%{id: "1", title: "T", priority: "none"}).priority == :none
    end
  end

  describe "status transitions" do
    test "start/1 transitions pending to in_progress" do
      ticket = Ticket.new(%{id: "1", title: "T"})
      assert ticket.status == :pending
      assert is_nil(ticket.timestamps.started_at)

      started = Ticket.start(ticket)
      assert started.status == :in_progress
      assert %DateTime{} = started.timestamps.started_at
    end

    test "start/1 is idempotent for non-pending tickets" do
      ticket = %{Ticket.new(%{id: "1", title: "T"}) | status: :completed}
      result = Ticket.start(ticket)
      assert result.status == :completed
    end

    test "complete/1 marks ticket as completed with timestamp" do
      ticket = Ticket.new(%{id: "1", title: "T"})
      completed = Ticket.complete(ticket)

      assert completed.status == :completed
      assert %DateTime{} = completed.timestamps.completed_at
      assert %DateTime{} = completed.timestamps.started_at
    end

    test "reset/1 clears timestamps and sets status to pending" do
      ticket = Ticket.new(%{id: "1", title: "T"}) |> Ticket.start() |> Ticket.complete()
      assert ticket.status == :completed

      reset = Ticket.reset(ticket)
      assert reset.status == :pending
      assert reset.timestamps.started_at == nil
      assert reset.timestamps.completed_at == nil
    end
  end

  describe "to_json/1 and from_json/1" do
    test "round-trips ticket data" do
      original =
        Ticket.new(%{
          id: "1",
          title: "Test ticket",
          description: "Description",
          type: "bugfix",
          priority: "high",
          estimate: 5,
          labels: ["backend"],
          acceptance_criteria: ["Criterion 1"],
          files: %{create: ["lib/test.ex"], modify: []},
          dependencies: %{blocked_by: [], blocks: ["2"]}
        })

      json = Ticket.to_json(original)
      restored = Ticket.from_json(json)

      assert restored.id == original.id
      assert restored.title == original.title
      assert restored.description == original.description
      assert restored.type == original.type
      assert restored.priority == original.priority
      assert restored.estimate == original.estimate
      assert restored.labels == original.labels
      assert restored.acceptance_criteria == original.acceptance_criteria
      assert restored.files.create == original.files.create
      assert restored.dependencies.blocks == original.dependencies.blocks
    end

    test "to_json produces valid JSON structure" do
      ticket = Ticket.new(%{id: "1", title: "Test"})
      json = Ticket.to_json(ticket)

      assert json["id"] == "1"
      assert json["title"] == "Test"
      assert json["status"] == "pending"
      assert json["type"] == "feature"
      assert is_map(json["timestamps"])
      assert is_binary(json["timestamps"]["created_at"])
    end
  end

  describe "statuses/0, types/0, priorities/0" do
    test "returns valid status list" do
      assert :pending in Ticket.statuses()
      assert :in_progress in Ticket.statuses()
      assert :completed in Ticket.statuses()
    end

    test "returns valid type list" do
      assert :feature in Ticket.types()
      assert :bugfix in Ticket.types()
      assert :chore in Ticket.types()
    end

    test "returns valid priority list" do
      assert :urgent in Ticket.priorities()
      assert :high in Ticket.priorities()
      assert :medium in Ticket.priorities()
      assert :low in Ticket.priorities()
      assert :none in Ticket.priorities()
    end
  end
end
