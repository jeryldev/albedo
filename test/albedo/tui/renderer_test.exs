defmodule Albedo.TUI.RendererTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Albedo.Tickets.Ticket
  alias Albedo.TUI.{Renderer, State}

  describe "render/1" do
    test "renders basic state without crashing" do
      state = State.new()

      output = capture_io(fn -> Renderer.render(state) end)

      assert is_binary(output)
      assert output =~ "Albedo TUI"
    end

    test "renders with projects panel active" do
      projects = [
        %{id: "test-project-1", state: "completed", task: "First task"},
        %{id: "test-project-2", state: "planning", task: "Second task"}
      ]

      state = %State{State.new() | projects: projects, active_panel: :projects}

      output = capture_io(fn -> Renderer.render(state) end)

      assert output =~ "Projects"
      assert output =~ "Tickets"
    end

    test "renders with tickets panel active and data" do
      ticket = Ticket.new(%{id: "1", title: "Test Ticket"})
      data = build_tickets_data([ticket])
      state = %State{State.new() | data: data, active_panel: :tickets}

      output = capture_io(fn -> Renderer.render(state) end)

      assert output =~ "Tickets"
      assert output =~ "Detail"
    end

    test "renders with detail panel active" do
      ticket =
        Ticket.new(%{
          id: "1",
          title: "Test Ticket",
          description: "A test description",
          type: "feature",
          priority: "high",
          estimate: 5
        })

      data = build_tickets_data([ticket])
      state = %State{State.new() | data: data, active_panel: :detail, selected_ticket: 0}

      output = capture_io(fn -> Renderer.render(state) end)

      assert output =~ "Detail"
    end

    test "renders with message set" do
      state = State.new() |> State.set_message("Test message")

      output = capture_io(fn -> Renderer.render(state) end)

      assert output =~ "Test message"
    end

    test "renders in edit mode" do
      ticket = Ticket.new(%{id: "1", title: "Editable Ticket"})
      data = build_tickets_data([ticket])

      state = %State{
        State.new()
        | data: data,
          mode: :edit,
          edit_field: :title,
          edit_buffer: "Editable Ticket",
          edit_cursor: 0
      }

      output = capture_io(fn -> Renderer.render(state) end)

      assert output =~ "Edit Ticket"
    end

    test "renders in input mode" do
      state = State.enter_input_mode(State.new(), :new_project, "Enter task: ")

      output = capture_io(fn -> Renderer.render(state) end)

      assert output =~ "Enter task:"
    end

    test "renders in confirm mode" do
      state = State.enter_confirm_mode(State.new(), :delete_project, "Delete project? (y/n)")

      output = capture_io(fn -> Renderer.render(state) end)

      assert output =~ "Delete project?"
    end

    test "renders help text for projects panel" do
      state = %State{State.new() | active_panel: :projects}

      output = capture_io(fn -> Renderer.render(state) end)

      assert output =~ "j/k:nav"
      assert output =~ "Tab:panel"
    end

    test "renders help text for tickets panel" do
      state = %State{State.new() | active_panel: :tickets}

      output = capture_io(fn -> Renderer.render(state) end)

      assert output =~ "j/k:nav"
    end

    test "renders help text for detail panel" do
      state = %State{State.new() | active_panel: :detail}

      output = capture_io(fn -> Renderer.render(state) end)

      assert output =~ "scroll"
    end

    test "renders project with different states" do
      projects = [
        %{id: "completed-project", state: "completed", task: "Done"},
        %{id: "failed-project", state: "failed", task: "Error"},
        %{id: "paused-project", state: "paused", task: "Waiting"},
        %{id: "planning-project", state: "planning", task: "Active"}
      ]

      state = %State{State.new() | projects: projects, active_panel: :projects}

      output = capture_io(fn -> Renderer.render(state) end)

      assert is_binary(output)
    end

    test "renders tickets with different statuses" do
      tickets = [
        Ticket.new(%{id: "1", title: "Pending", status: "pending"}),
        %{Ticket.new(%{id: "2", title: "In Progress"}) | status: :in_progress},
        %{Ticket.new(%{id: "3", title: "Completed"}) | status: :completed}
      ]

      data = build_tickets_data(tickets)
      state = %State{State.new() | data: data, active_panel: :tickets}

      output = capture_io(fn -> Renderer.render(state) end)

      assert is_binary(output)
    end

    test "renders ticket with labels" do
      ticket =
        Ticket.new(%{
          id: "1",
          title: "Labeled Ticket",
          labels: ["backend", "urgent"]
        })

      data = build_tickets_data([ticket])
      state = %State{State.new() | data: data, active_panel: :detail}

      output = capture_io(fn -> Renderer.render(state) end)

      assert is_binary(output)
    end

    test "renders ticket with files" do
      ticket =
        Ticket.new(%{
          id: "1",
          title: "Files Ticket",
          files: %{create: ["lib/new.ex"], modify: ["lib/existing.ex"]}
        })

      data = build_tickets_data([ticket])
      state = %State{State.new() | data: data, active_panel: :detail}

      output = capture_io(fn -> Renderer.render(state) end)

      assert is_binary(output)
    end

    test "renders ticket with dependencies" do
      ticket =
        Ticket.new(%{
          id: "1",
          title: "Deps Ticket",
          dependencies: %{blocked_by: ["0"], blocks: ["2"]}
        })

      data = build_tickets_data([ticket])
      state = %State{State.new() | data: data, active_panel: :detail}

      output = capture_io(fn -> Renderer.render(state) end)

      assert is_binary(output)
    end

    test "renders ticket with acceptance criteria" do
      ticket =
        Ticket.new(%{
          id: "1",
          title: "AC Ticket",
          acceptance_criteria: ["First criterion", "Second criterion"]
        })

      data = build_tickets_data([ticket])
      state = %State{State.new() | data: data, active_panel: :detail}

      output = capture_io(fn -> Renderer.render(state) end)

      assert is_binary(output)
    end

    test "renders with scrolled detail panel" do
      ticket =
        Ticket.new(%{
          id: "1",
          title: "Scrollable Ticket",
          description: String.duplicate("Long description. ", 50)
        })

      data = build_tickets_data([ticket])
      state = %State{State.new() | data: data, active_panel: :detail, detail_scroll: 5}

      output = capture_io(fn -> Renderer.render(state) end)

      assert is_binary(output)
    end

    test "renders edit mode with cursor position" do
      ticket = Ticket.new(%{id: "1", title: "Edit Me"})
      data = build_tickets_data([ticket])

      state = %State{
        State.new()
        | data: data,
          mode: :edit,
          edit_field: :title,
          edit_buffer: "Edit Me",
          edit_cursor: 3
      }

      output = capture_io(fn -> Renderer.render(state) end)

      assert is_binary(output)
    end
  end

  defp build_tickets_data(tickets) do
    %{
      project_id: "test-project",
      task_description: "Test task",
      tickets: tickets,
      summary: %{
        total: length(tickets),
        pending: length(tickets),
        in_progress: 0,
        completed: 0,
        total_points: 0,
        completed_points: 0
      }
    }
  end
end
