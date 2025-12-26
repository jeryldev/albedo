defmodule Albedo.TicketsTest do
  use ExUnit.Case, async: true

  alias Albedo.Tickets
  alias Albedo.Tickets.Ticket

  @test_dir System.tmp_dir!() <> "/albedo_tickets_test_#{System.unique_integer([:positive])}"

  setup do
    File.mkdir_p!(@test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)

    {:ok, project_dir: @test_dir}
  end

  describe "new/3" do
    test "creates tickets data with summary" do
      tickets = [
        Ticket.new(%{id: "1", title: "Ticket 1", estimate: 3}),
        Ticket.new(%{id: "2", title: "Ticket 2", estimate: 5})
      ]

      data = Tickets.new("test-project", "Test task", tickets)

      assert data.version == "1.0"
      assert data.project_id == "test-project"
      assert data.task_description == "Test task"
      assert data.summary.total == 2
      assert data.summary.pending == 2
      assert data.summary.in_progress == 0
      assert data.summary.completed == 0
      assert data.summary.total_points == 8
      assert data.summary.completed_points == 0
      assert length(data.tickets) == 2
    end

    test "accepts project_name option" do
      tickets = [Ticket.new(%{id: "1", title: "Ticket 1"})]
      data = Tickets.new("test-project", "Test task", tickets, project_name: "my_app")

      assert data.project_name == "my_app"
    end
  end

  describe "save/2 and load/1" do
    test "saves and loads tickets data", %{project_dir: project_dir} do
      tickets = [
        Ticket.new(%{id: "1", title: "Ticket 1", estimate: 3}),
        Ticket.new(%{id: "2", title: "Ticket 2", estimate: 5})
      ]

      data = Tickets.new("test-project", "Test task", tickets)

      assert :ok = Tickets.save(project_dir, data)
      assert File.exists?(Path.join(project_dir, "tickets.json"))

      {:ok, loaded} = Tickets.load(project_dir)

      assert loaded.project_id == "test-project"
      assert loaded.task_description == "Test task"
      assert length(loaded.tickets) == 2
      assert loaded.summary.total == 2
    end

    test "load returns error for missing file", %{project_dir: project_dir} do
      assert {:error, :not_found} = Tickets.load(project_dir)
    end
  end

  describe "list/2" do
    test "returns all tickets by default" do
      tickets = [
        Ticket.new(%{id: "1", title: "Ticket 1"}),
        Ticket.new(%{id: "2", title: "Ticket 2"})
      ]

      data = Tickets.new("test", "task", tickets)
      result = Tickets.list(data)

      assert length(result) == 2
    end

    test "filters by status" do
      tickets = [
        Ticket.new(%{id: "1", title: "Pending", status: :pending}),
        %{Ticket.new(%{id: "2", title: "In Progress"}) | status: :in_progress},
        %{Ticket.new(%{id: "3", title: "Completed"}) | status: :completed}
      ]

      data = Tickets.new("test", "task", tickets)

      pending = Tickets.list(data, status: :pending)
      assert length(pending) == 1
      assert hd(pending).title == "Pending"

      in_progress = Tickets.list(data, status: "in_progress")
      assert length(in_progress) == 1

      multiple = Tickets.list(data, status: "pending,in_progress")
      assert length(multiple) == 2
    end
  end

  describe "get/2" do
    test "returns ticket by id" do
      tickets = [
        Ticket.new(%{id: "1", title: "First"}),
        Ticket.new(%{id: "2", title: "Second"})
      ]

      data = Tickets.new("test", "task", tickets)

      assert Tickets.get(data, "1").title == "First"
      assert Tickets.get(data, "2").title == "Second"
      assert Tickets.get(data, 1).title == "First"
      assert Tickets.get(data, "3") == nil
    end
  end

  describe "start/2, complete/2, reset/2" do
    test "start transitions ticket to in_progress" do
      tickets = [Ticket.new(%{id: "1", title: "Test"})]
      data = Tickets.new("test", "task", tickets)

      {:ok, updated_data, ticket} = Tickets.start(data, "1")

      assert ticket.status == :in_progress
      assert updated_data.summary.in_progress == 1
      assert updated_data.summary.pending == 0
    end

    test "complete transitions ticket to completed" do
      tickets = [Ticket.new(%{id: "1", title: "Test", estimate: 5})]
      data = Tickets.new("test", "task", tickets)

      {:ok, updated_data, ticket} = Tickets.complete(data, "1")

      assert ticket.status == :completed
      assert updated_data.summary.completed == 1
      assert updated_data.summary.completed_points == 5
    end

    test "reset transitions ticket to pending" do
      tickets = [%{Ticket.new(%{id: "1", title: "Test"}) | status: :completed}]
      data = Tickets.new("test", "task", tickets)

      {:ok, updated_data, ticket} = Tickets.reset(data, "1")

      assert ticket.status == :pending
      assert updated_data.summary.pending == 1
      assert updated_data.summary.completed == 0
    end

    test "returns error for non-existent ticket" do
      data = Tickets.new("test", "task", [])

      assert {:error, :not_found} = Tickets.start(data, "999")
      assert {:error, :not_found} = Tickets.complete(data, "999")
      assert {:error, :not_found} = Tickets.reset(data, "999")
    end
  end

  describe "reset_all/1" do
    test "resets all tickets to pending" do
      tickets = [
        %{Ticket.new(%{id: "1", title: "T1"}) | status: :completed},
        %{Ticket.new(%{id: "2", title: "T2"}) | status: :in_progress}
      ]

      data = Tickets.new("test", "task", tickets)
      updated = Tickets.reset_all(data)

      assert Enum.all?(updated.tickets, &(&1.status == :pending))
      assert updated.summary.pending == 2
      assert updated.summary.in_progress == 0
      assert updated.summary.completed == 0
    end
  end

  describe "add/2" do
    @describetag :add

    setup do
      existing_ticket = Ticket.new(%{id: "1", title: "Existing ticket", estimate: 3})
      data = Tickets.new("test-project", "Test task", [existing_ticket])
      {:ok, data: data, existing_ticket: existing_ticket}
    end

    test "given existing tickets, when adding new ticket, then auto-generates next id", %{
      data: data
    } do
      {:ok, updated_data, ticket} = Tickets.add(data, %{title: "New ticket"})

      assert ticket.id == "2"
      assert ticket.title == "New ticket"
      assert ticket.status == :pending
      assert length(updated_data.tickets) == 2
    end

    test "given empty ticket list, when adding first ticket, then generates id 1" do
      empty_data = Tickets.new("test", "task", [])

      {:ok, updated_data, ticket} = Tickets.add(empty_data, %{title: "First ticket"})

      assert ticket.id == "1"
      assert length(updated_data.tickets) == 1
    end

    test "given all attributes provided, when adding ticket, then all fields are set correctly" do
      empty_data = Tickets.new("test", "task", [])

      attrs = %{
        title: "Bug fix",
        description: "Fix the login issue",
        priority: "high",
        estimate: 5,
        type: "bugfix",
        labels: "auth,urgent"
      }

      {:ok, _updated_data, ticket} = Tickets.add(empty_data, attrs)

      assert ticket.title == "Bug fix"
      assert ticket.description == "Fix the login issue"
      assert ticket.priority == :high
      assert ticket.estimate == 5
      assert ticket.type == :bugfix
      assert ticket.labels == ["auth", "urgent"]
    end

    test "given existing tickets with points, when adding ticket with points, then summary is updated",
         %{data: data} do
      {:ok, updated_data, _ticket} = Tickets.add(data, %{title: "T2", estimate: 5})

      assert updated_data.summary.total == 2
      assert updated_data.summary.pending == 2
      assert updated_data.summary.total_points == 8
    end

    test "given non-sequential ticket ids, when adding ticket, then uses max id + 1" do
      tickets = [
        Ticket.new(%{id: "5", title: "T5"}),
        Ticket.new(%{id: "10", title: "T10"})
      ]

      data = Tickets.new("test", "task", tickets)

      {:ok, _updated_data, ticket} = Tickets.add(data, %{title: "New"})

      assert ticket.id == "11"
    end
  end

  describe "delete/2" do
    @describetag :delete

    setup do
      tickets = [
        Ticket.new(%{id: "1", title: "First ticket", estimate: 3}),
        Ticket.new(%{id: "2", title: "Second ticket", estimate: 5}),
        Ticket.new(%{id: "3", title: "Third ticket", estimate: 8})
      ]

      data = Tickets.new("test-project", "Test task", tickets)
      {:ok, data: data}
    end

    test "given existing ticket, when deleting by id, then removes ticket and returns it", %{
      data: data
    } do
      {:ok, updated_data, deleted_ticket} = Tickets.delete(data, "2")

      assert deleted_ticket.id == "2"
      assert deleted_ticket.title == "Second ticket"
      assert length(updated_data.tickets) == 2
      refute Enum.any?(updated_data.tickets, &(&1.id == "2"))
    end

    test "given existing ticket, when deleting, then summary is recalculated", %{data: data} do
      assert data.summary.total == 3
      assert data.summary.total_points == 16

      {:ok, updated_data, _deleted} = Tickets.delete(data, "2")

      assert updated_data.summary.total == 2
      assert updated_data.summary.total_points == 11
    end

    test "given non-existent ticket id, when deleting, then returns not_found error", %{
      data: data
    } do
      assert {:error, :not_found} = Tickets.delete(data, "999")
    end

    test "given integer id, when deleting, then converts to string and finds ticket", %{
      data: data
    } do
      {:ok, updated_data, deleted_ticket} = Tickets.delete(data, 1)

      assert deleted_ticket.id == "1"
      assert length(updated_data.tickets) == 2
    end

    test "given multiple deletions, when deleting sequentially, then each deletion works correctly",
         %{data: data} do
      {:ok, data_after_first, _} = Tickets.delete(data, "1")
      {:ok, data_after_second, _} = Tickets.delete(data_after_first, "2")

      assert length(data_after_second.tickets) == 1
      assert hd(data_after_second.tickets).id == "3"
    end
  end

  describe "edit/3" do
    @describetag :edit

    setup do
      tickets = [
        Ticket.new(%{id: "1", title: "First ticket", description: "Original desc", estimate: 3}),
        Ticket.new(%{id: "2", title: "Second ticket", estimate: 5})
      ]

      data = Tickets.new("test-project", "Test task", tickets)
      {:ok, data: data}
    end

    test "given existing ticket, when editing title, then updates ticket and returns it", %{
      data: data
    } do
      {:ok, updated_data, ticket} = Tickets.edit(data, "1", %{title: "New title"})

      assert ticket.title == "New title"
      assert ticket.description == "Original desc"
      assert Tickets.get(updated_data, "1").title == "New title"
    end

    test "given existing ticket, when editing description, then updates only description", %{
      data: data
    } do
      {:ok, updated_data, ticket} = Tickets.edit(data, "1", %{description: "New description"})

      assert ticket.description == "New description"
      assert ticket.title == "First ticket"
      assert Tickets.get(updated_data, "1").description == "New description"
    end

    test "given existing ticket, when editing priority, then updates priority and recalculates summary",
         %{data: data} do
      {:ok, updated_data, ticket} = Tickets.edit(data, "1", %{priority: :high})

      assert ticket.priority == :high
      assert updated_data.summary.total == 2
    end

    test "given existing ticket, when editing points, then updates estimate and recalculates summary",
         %{data: data} do
      {:ok, updated_data, ticket} = Tickets.edit(data, "1", %{points: 8})

      assert ticket.estimate == 8
      assert updated_data.summary.total_points == 13
    end

    test "given existing ticket, when editing status to completed, then updates summary", %{
      data: data
    } do
      {:ok, updated_data, ticket} = Tickets.edit(data, "1", %{status: :completed})

      assert ticket.status == :completed
      assert updated_data.summary.completed == 1
      assert updated_data.summary.completed_points == 3
    end

    test "given existing ticket, when editing type, then updates type", %{data: data} do
      {:ok, _updated_data, ticket} = Tickets.edit(data, "1", %{type: :bugfix})

      assert ticket.type == :bugfix
    end

    test "given existing ticket, when editing labels with string, then parses labels", %{
      data: data
    } do
      {:ok, _updated_data, ticket} = Tickets.edit(data, "1", %{labels: "api,backend"})

      assert ticket.labels == ["api", "backend"]
    end

    test "given existing ticket, when editing multiple fields, then updates all fields", %{
      data: data
    } do
      changes = %{
        title: "Updated title",
        description: "Updated desc",
        priority: :urgent,
        points: 13,
        type: :bugfix,
        labels: ["critical"]
      }

      {:ok, updated_data, ticket} = Tickets.edit(data, "1", changes)

      assert ticket.title == "Updated title"
      assert ticket.description == "Updated desc"
      assert ticket.priority == :urgent
      assert ticket.estimate == 13
      assert ticket.type == :bugfix
      assert ticket.labels == ["critical"]
      assert updated_data.summary.total_points == 18
    end

    test "given integer id, when editing, then converts to string and finds ticket", %{data: data} do
      {:ok, _updated_data, ticket} = Tickets.edit(data, 1, %{title: "Updated"})

      assert ticket.title == "Updated"
    end

    test "given non-existent ticket id, when editing, then returns not_found error", %{data: data} do
      assert {:error, :not_found} = Tickets.edit(data, "999", %{title: "New"})
    end
  end

  describe "compute_summary/1" do
    test "calculates correct summary" do
      tickets = [
        %{Ticket.new(%{id: "1", title: "T1", estimate: 3}) | status: :pending},
        %{Ticket.new(%{id: "2", title: "T2", estimate: 5}) | status: :in_progress},
        %{Ticket.new(%{id: "3", title: "T3", estimate: 8}) | status: :completed}
      ]

      summary = Tickets.compute_summary(tickets)

      assert summary.total == 3
      assert summary.pending == 1
      assert summary.in_progress == 1
      assert summary.completed == 1
      assert summary.total_points == 16
      assert summary.completed_points == 8
    end

    test "handles nil estimates" do
      tickets = [
        Ticket.new(%{id: "1", title: "T1"}),
        Ticket.new(%{id: "2", title: "T2", estimate: 5})
      ]

      summary = Tickets.compute_summary(tickets)

      assert summary.total == 2
      assert summary.total_points == 5
    end
  end
end
