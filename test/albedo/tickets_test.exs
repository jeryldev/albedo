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

    {:ok, session_dir: @test_dir}
  end

  describe "new/3" do
    test "creates tickets data with summary" do
      tickets = [
        Ticket.new(%{id: "1", title: "Ticket 1", estimate: 3}),
        Ticket.new(%{id: "2", title: "Ticket 2", estimate: 5})
      ]

      data = Tickets.new("test-session", "Test task", tickets)

      assert data.version == "1.0"
      assert data.session_id == "test-session"
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
      data = Tickets.new("test-session", "Test task", tickets, project_name: "my_app")

      assert data.project_name == "my_app"
    end
  end

  describe "save/2 and load/1" do
    test "saves and loads tickets data", %{session_dir: session_dir} do
      tickets = [
        Ticket.new(%{id: "1", title: "Ticket 1", estimate: 3}),
        Ticket.new(%{id: "2", title: "Ticket 2", estimate: 5})
      ]

      data = Tickets.new("test-session", "Test task", tickets)

      assert :ok = Tickets.save(session_dir, data)
      assert File.exists?(Path.join(session_dir, "tickets.json"))

      {:ok, loaded} = Tickets.load(session_dir)

      assert loaded.session_id == "test-session"
      assert loaded.task_description == "Test task"
      assert length(loaded.tickets) == 2
      assert loaded.summary.total == 2
    end

    test "load returns error for missing file", %{session_dir: session_dir} do
      assert {:error, :not_found} = Tickets.load(session_dir)
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
