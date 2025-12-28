defmodule Albedo.TUI.StateTest do
  use ExUnit.Case, async: true

  alias Albedo.Tickets.Ticket
  alias Albedo.TUI.State

  describe "new/1" do
    test "creates a new state with defaults" do
      state = State.new()

      assert state.project_dir == nil
      assert state.data == nil
      assert state.projects == []
      assert state.current_project == 0
      assert state.selected_ticket == nil
      assert state.active_panel == :projects
      assert state.mode == :normal
      assert state.quit == false
    end

    test "accepts project_dir option" do
      state = State.new(project_dir: "/tmp/test")

      assert state.project_dir == "/tmp/test"
    end
  end

  describe "move_up/1" do
    test "decrements current_project when in projects panel" do
      state = %State{State.new() | current_project: 2, active_panel: :projects}

      result = State.move_up(state)

      assert result.current_project == 1
    end

    test "does not go below 0 for projects" do
      state = %State{State.new() | current_project: 0, active_panel: :projects}

      result = State.move_up(state)

      assert result.current_project == 0
    end

    test "decrements selected_ticket when in tickets panel with data" do
      data = build_tickets_data([build_ticket("1"), build_ticket("2")])
      state = %State{State.new() | selected_ticket: 1, active_panel: :tickets, data: data}

      result = State.move_up(state)

      assert result.selected_ticket == 0
    end

    test "does nothing when in tickets panel without data" do
      state = %State{State.new() | active_panel: :tickets, data: nil}

      result = State.move_up(state)

      assert result.selected_ticket == nil
    end
  end

  describe "move_down/1" do
    test "increments current_project when in projects panel" do
      projects = [%{id: "a"}, %{id: "b"}, %{id: "c"}]

      state = %State{
        State.new()
        | current_project: 0,
          active_panel: :projects,
          projects: projects
      }

      result = State.move_down(state)

      assert result.current_project == 1
    end

    test "does not exceed project count" do
      projects = [%{id: "a"}, %{id: "b"}]

      state = %State{
        State.new()
        | current_project: 1,
          active_panel: :projects,
          projects: projects
      }

      result = State.move_down(state)

      assert result.current_project == 1
    end

    test "increments selected_ticket when in tickets panel with data" do
      data = build_tickets_data([build_ticket("1"), build_ticket("2")])
      state = %State{State.new() | selected_ticket: 0, active_panel: :tickets, data: data}

      result = State.move_down(state)

      assert result.selected_ticket == 1
    end

    test "does not exceed ticket count" do
      data = build_tickets_data([build_ticket("1")])
      state = %State{State.new() | selected_ticket: 0, active_panel: :tickets, data: data}

      result = State.move_down(state)

      assert result.selected_ticket == 0
    end
  end

  describe "next_panel/1" do
    test "cycles projects -> tickets -> research -> detail -> projects" do
      state = State.new()

      assert state.active_panel == :projects
      assert State.next_panel(state).active_panel == :tickets
      assert State.next_panel(State.next_panel(state)).active_panel == :research
      assert State.next_panel(State.next_panel(State.next_panel(state))).active_panel == :detail

      assert State.next_panel(State.next_panel(State.next_panel(State.next_panel(state)))).active_panel ==
               :projects
    end
  end

  describe "prev_panel/1" do
    test "cycles projects -> detail -> research -> tickets -> projects" do
      state = State.new()

      assert state.active_panel == :projects
      assert State.prev_panel(state).active_panel == :detail
      assert State.prev_panel(State.prev_panel(state)).active_panel == :research
      assert State.prev_panel(State.prev_panel(State.prev_panel(state))).active_panel == :tickets

      assert State.prev_panel(State.prev_panel(State.prev_panel(State.prev_panel(state)))).active_panel ==
               :projects
    end
  end

  describe "current_project/1" do
    test "returns the currently selected project" do
      projects = [%{id: "a"}, %{id: "b"}]
      state = %State{State.new() | projects: projects, current_project: 1}

      assert State.current_project(state) == %{id: "b"}
    end

    test "returns nil when no projects" do
      state = State.new()

      assert State.current_project(state) == nil
    end
  end

  describe "current_ticket/1" do
    test "returns the currently selected ticket" do
      ticket1 = build_ticket("1")
      ticket2 = build_ticket("2")
      data = build_tickets_data([ticket1, ticket2])
      state = %State{State.new() | data: data, selected_ticket: 1}

      assert State.current_ticket(state).id == "2"
    end

    test "returns nil when no data" do
      state = State.new()

      assert State.current_ticket(state) == nil
    end
  end

  describe "set_message/2" do
    test "sets message" do
      state = State.new()

      state = State.set_message(state, "Hello")
      assert state.message == "Hello"
    end
  end

  describe "quit/1" do
    test "sets quit flag" do
      state = State.new()

      result = State.quit(state)

      assert result.quit == true
    end
  end

  defp build_ticket(id) do
    Ticket.new(%{id: id, title: "Test #{id}"})
  end

  describe "editable_fields/0" do
    test "returns list of editable field atoms" do
      fields = State.editable_fields()

      assert :title in fields
      assert :description in fields
      assert :type in fields
      assert :priority in fields
      assert :estimate in fields
      assert :labels in fields
    end
  end

  describe "scroll functions" do
    test "reset_detail_scroll sets detail_scroll to 0" do
      state = %State{State.new() | detail_scroll: 10}

      result = State.reset_detail_scroll(state)

      assert result.detail_scroll == 0
    end

    test "move_up in detail panel decrements detail_scroll" do
      state = %State{State.new() | active_panel: :detail, detail_scroll: 5}

      result = State.move_up(state)

      assert result.detail_scroll == 4
    end

    test "move_down in detail panel increments detail_scroll" do
      state = %State{State.new() | active_panel: :detail, detail_scroll: 0}

      result = State.move_down(state)

      assert result.detail_scroll == 1
    end
  end

  describe "edit mode functions" do
    test "enter_edit_mode sets mode to :edit with ticket data" do
      ticket = build_ticket("1")
      data = build_tickets_data([ticket])
      state = %State{State.new() | data: data, selected_ticket: 0}

      result = State.enter_edit_mode(state)

      assert result.mode == :edit
      assert result.edit_field == :title
      assert result.edit_buffer == ticket.title
      assert result.edit_cursor == String.length(ticket.title)
    end

    test "enter_edit_mode does nothing when no ticket selected" do
      state = State.new()

      result = State.enter_edit_mode(state)

      assert result.mode == :normal
      assert result.edit_field == nil
    end

    test "enter_edit_mode handles nil title gracefully" do
      ticket = %{build_ticket("1") | title: nil}
      data = build_tickets_data([ticket])
      state = %State{State.new() | data: data, selected_ticket: 0}

      result = State.enter_edit_mode(state)

      assert result.mode == :edit
      assert result.edit_field == :title
      assert result.edit_buffer == ""
      assert result.edit_cursor == 0
    end

    test "exit_edit_mode resets edit state" do
      state = %State{
        State.new()
        | mode: :edit,
          edit_field: :title,
          edit_buffer: "test",
          edit_cursor: 4
      }

      result = State.exit_edit_mode(state)

      assert result.mode == :normal
      assert result.edit_field == nil
      assert result.edit_buffer == nil
      assert result.edit_cursor == 0
    end

    test "next_edit_field cycles through editable fields" do
      ticket = build_ticket("1")
      data = build_tickets_data([ticket])

      state = %State{
        State.new()
        | data: data,
          selected_ticket: 0,
          mode: :edit,
          edit_field: :title,
          edit_buffer: "test"
      }

      result = State.next_edit_field(state)

      assert result.edit_field == :description
    end

    test "prev_edit_field cycles backwards through editable fields" do
      ticket = build_ticket("1")
      data = build_tickets_data([ticket])

      state = %State{
        State.new()
        | data: data,
          selected_ticket: 0,
          mode: :edit,
          edit_field: :title,
          edit_buffer: "test"
      }

      result = State.prev_edit_field(state)

      assert result.edit_field == :labels
    end

    test "edit_insert_char inserts character at cursor" do
      state = %State{State.new() | edit_buffer: "helo", edit_cursor: 3}

      result = State.edit_insert_char(state, "l")

      assert result.edit_buffer == "hello"
      assert result.edit_cursor == 4
    end

    test "edit_delete_char removes character before cursor" do
      state = %State{State.new() | edit_buffer: "hello", edit_cursor: 5}

      result = State.edit_delete_char(state)

      assert result.edit_buffer == "hell"
      assert result.edit_cursor == 4
    end

    test "edit_delete_char does nothing at position 0" do
      state = %State{State.new() | edit_buffer: "hello", edit_cursor: 0}

      result = State.edit_delete_char(state)

      assert result.edit_buffer == "hello"
      assert result.edit_cursor == 0
    end

    test "edit_move_cursor_left decrements cursor" do
      state = %State{State.new() | edit_buffer: "hello", edit_cursor: 3}

      result = State.edit_move_cursor_left(state)

      assert result.edit_cursor == 2
    end

    test "edit_move_cursor_left does not go below 0" do
      state = %State{State.new() | edit_buffer: "hello", edit_cursor: 0}

      result = State.edit_move_cursor_left(state)

      assert result.edit_cursor == 0
    end

    test "edit_move_cursor_right increments cursor" do
      state = %State{State.new() | edit_buffer: "hello", edit_cursor: 2}

      result = State.edit_move_cursor_right(state)

      assert result.edit_cursor == 3
    end

    test "edit_move_cursor_right does not exceed buffer length" do
      state = %State{State.new() | edit_buffer: "hello", edit_cursor: 5}

      result = State.edit_move_cursor_right(state)

      assert result.edit_cursor == 5
    end

    test "edit_cursor_home moves cursor to 0" do
      state = %State{State.new() | edit_buffer: "hello", edit_cursor: 3}

      result = State.edit_cursor_home(state)

      assert result.edit_cursor == 0
    end

    test "edit_cursor_end moves cursor to end of buffer" do
      state = %State{State.new() | edit_buffer: "hello", edit_cursor: 0}

      result = State.edit_cursor_end(state)

      assert result.edit_cursor == 5
    end

    test "get_edit_changes returns map with current field and buffer value" do
      state = %State{State.new() | edit_field: :title, edit_buffer: "New Title"}

      result = State.get_edit_changes(state)

      assert result == %{title: "New Title"}
    end

    test "get_edit_changes parses labels as list" do
      state = %State{State.new() | edit_field: :labels, edit_buffer: "backend, frontend"}

      result = State.get_edit_changes(state)

      assert result == %{labels: ["backend", "frontend"]}
    end

    test "get_edit_changes parses estimate as integer" do
      state = %State{State.new() | edit_field: :estimate, edit_buffer: "5"}

      result = State.get_edit_changes(state)

      assert result == %{estimate: 5}
    end

    test "get_edit_changes returns nil for empty estimate" do
      state = %State{State.new() | edit_field: :estimate, edit_buffer: ""}

      result = State.get_edit_changes(state)

      assert result == %{estimate: nil}
    end

    test "get_edit_changes parses type as atom" do
      state = %State{State.new() | edit_field: :type, edit_buffer: "bugfix"}

      result = State.get_edit_changes(state)

      assert result == %{type: :bugfix}
    end

    test "get_edit_changes parses priority as atom" do
      state = %State{State.new() | edit_field: :priority, edit_buffer: "high"}

      result = State.get_edit_changes(state)

      assert result == %{priority: :high}
    end
  end

  describe "input mode functions" do
    test "enter_input_mode sets mode to :input with prompt" do
      state = State.new()

      result = State.enter_input_mode(state, :new_project, "Enter task: ")

      assert result.mode == :input
      assert result.input_mode == :new_project
      assert result.input_prompt == "Enter task: "
      assert result.input_buffer == ""
      assert result.input_cursor == 0
    end

    test "exit_input_mode resets input state" do
      state = %State{
        State.new()
        | mode: :input,
          input_mode: :new_project,
          input_prompt: "Enter task: ",
          input_buffer: "test",
          input_cursor: 4
      }

      result = State.exit_input_mode(state)

      assert result.mode == :normal
      assert result.input_mode == nil
      assert result.input_prompt == nil
      assert result.input_buffer == nil
      assert result.input_cursor == 0
    end

    test "input_insert_char inserts character at cursor" do
      state = %State{State.new() | input_buffer: "helo", input_cursor: 3}

      result = State.input_insert_char(state, "l")

      assert result.input_buffer == "hello"
      assert result.input_cursor == 4
    end

    test "input_delete_char removes character before cursor" do
      state = %State{State.new() | input_buffer: "hello", input_cursor: 5}

      result = State.input_delete_char(state)

      assert result.input_buffer == "hell"
      assert result.input_cursor == 4
    end

    test "input_delete_char does nothing at position 0" do
      state = %State{State.new() | input_buffer: "hello", input_cursor: 0}

      result = State.input_delete_char(state)

      assert result.input_buffer == "hello"
      assert result.input_cursor == 0
    end

    test "input_move_cursor_left decrements cursor" do
      state = %State{State.new() | input_buffer: "hello", input_cursor: 3}

      result = State.input_move_cursor_left(state)

      assert result.input_cursor == 2
    end

    test "input_move_cursor_left does not go below 0" do
      state = %State{State.new() | input_buffer: "hello", input_cursor: 0}

      result = State.input_move_cursor_left(state)

      assert result.input_cursor == 0
    end

    test "input_move_cursor_right increments cursor" do
      state = %State{State.new() | input_buffer: "hello", input_cursor: 2}

      result = State.input_move_cursor_right(state)

      assert result.input_cursor == 3
    end

    test "input_move_cursor_right does not exceed buffer length" do
      state = %State{State.new() | input_buffer: "hello", input_cursor: 5}

      result = State.input_move_cursor_right(state)

      assert result.input_cursor == 5
    end
  end

  describe "confirm mode functions" do
    test "enter_confirm_mode sets mode to :confirm with action and message" do
      state = State.new()

      result = State.enter_confirm_mode(state, :delete_project, "Delete project? (y/n)")

      assert result.mode == :confirm
      assert result.confirm_action == :delete_project
      assert result.confirm_message == "Delete project? (y/n)"
    end

    test "exit_confirm_mode resets confirm state" do
      state = %State{
        State.new()
        | mode: :confirm,
          confirm_action: :delete_project,
          confirm_message: "Delete?"
      }

      result = State.exit_confirm_mode(state)

      assert result.mode == :normal
      assert result.confirm_action == nil
      assert result.confirm_message == nil
    end
  end

  describe "load_projects/2" do
    setup do
      test_dir = Path.join(System.tmp_dir!(), "albedo_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      {:ok, projects_dir: test_dir}
    end

    test "loads projects from directory", %{projects_dir: projects_dir} do
      project_dir = Path.join(projects_dir, "test-project")
      File.mkdir_p!(project_dir)

      project_data = %{"state" => "planning", "task" => "Test task description"}
      File.write!(Path.join(project_dir, "project.json"), Jason.encode!(project_data))

      state = State.new()

      result = State.load_projects(state, projects_dir)

      assert length(result.projects) == 1
      assert result.projects_dir == projects_dir
      assert hd(result.projects).id == "test-project"
      assert hd(result.projects).state == "planning"
      assert hd(result.projects).task == "Test task description"
    end

    test "returns empty list when directory does not exist", %{projects_dir: projects_dir} do
      nonexistent_dir = Path.join(projects_dir, "nonexistent")
      state = State.new()

      result = State.load_projects(state, nonexistent_dir)

      assert result.projects == []
      assert result.projects_dir == nonexistent_dir
    end

    test "ignores hidden directories", %{projects_dir: projects_dir} do
      hidden_dir = Path.join(projects_dir, ".hidden-project")
      File.mkdir_p!(hidden_dir)
      File.write!(Path.join(hidden_dir, "project.json"), "{}")

      visible_dir = Path.join(projects_dir, "visible-project")
      File.mkdir_p!(visible_dir)
      File.write!(Path.join(visible_dir, "project.json"), "{}")

      state = State.new()

      result = State.load_projects(state, projects_dir)

      assert length(result.projects) == 1
      assert hd(result.projects).id == "visible-project"
    end

    test "ignores directories without project.json", %{projects_dir: projects_dir} do
      no_project_dir = Path.join(projects_dir, "no-project")
      File.mkdir_p!(no_project_dir)

      with_project_dir = Path.join(projects_dir, "with-project")
      File.mkdir_p!(with_project_dir)
      File.write!(Path.join(with_project_dir, "project.json"), "{}")

      state = State.new()

      result = State.load_projects(state, projects_dir)

      assert length(result.projects) == 1
      assert hd(result.projects).id == "with-project"
    end

    test "sorts projects by created_at descending (newest first)", %{projects_dir: projects_dir} do
      now = DateTime.utc_now()

      projects_data = [
        {"old-project", DateTime.add(now, -3600, :second)},
        {"new-project", now},
        {"mid-project", DateTime.add(now, -1800, :second)}
      ]

      for {name, created_at} <- projects_data do
        dir = Path.join(projects_dir, name)
        File.mkdir_p!(dir)

        data = %{"created_at" => DateTime.to_iso8601(created_at)}
        File.write!(Path.join(dir, "project.json"), Jason.encode!(data))
      end

      state = State.new()

      result = State.load_projects(state, projects_dir)

      ids = Enum.map(result.projects, & &1.id)
      assert ids == ["new-project", "mid-project", "old-project"]
    end

    test "truncates task to 50 characters", %{projects_dir: projects_dir} do
      project_dir = Path.join(projects_dir, "long-task-project")
      File.mkdir_p!(project_dir)

      long_task = String.duplicate("a", 100)
      project_data = %{"task" => long_task}
      File.write!(Path.join(project_dir, "project.json"), Jason.encode!(project_data))

      state = State.new()

      result = State.load_projects(state, projects_dir)

      assert String.length(hd(result.projects).task) == 50
    end
  end

  describe "load_tickets/2" do
    setup do
      test_dir = Path.join(System.tmp_dir!(), "albedo_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      {:ok, project_dir: test_dir}
    end

    test "loads tickets from project directory", %{project_dir: project_dir} do
      tickets_data = %{
        "project_id" => "test",
        "task_description" => "Test task",
        "tickets" => [
          %{"id" => "1", "title" => "Ticket 1", "status" => "pending"}
        ]
      }

      File.write!(Path.join(project_dir, "tickets.json"), Jason.encode!(tickets_data))

      state = State.new()

      {:ok, result} = State.load_tickets(state, project_dir)

      assert result.project_dir == project_dir
      assert result.selected_ticket == nil
      assert length(result.data.tickets) == 1
    end

    test "returns error when tickets file does not exist", %{project_dir: project_dir} do
      state = State.new()

      result = State.load_tickets(state, project_dir)

      assert {:error, _reason} = result
    end
  end

  describe "load_project_without_tickets/2" do
    setup do
      test_dir = Path.join(System.tmp_dir!(), "albedo_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      {:ok, project_dir: test_dir}
    end

    test "creates empty data structure for project", %{project_dir: project_dir} do
      project_id = Path.basename(project_dir)
      projects = [%{id: project_id, task: "Test task"}]
      state = %State{State.new() | projects: projects}

      result = State.load_project_without_tickets(state, project_dir)

      assert result.project_dir == project_dir
      assert result.data != nil
      assert result.data.tickets == []
      assert result.data.project_id == project_id
      assert result.data.task_description == "Test task"
    end

    test "resets selection state", %{project_dir: project_dir} do
      state = %State{
        State.new()
        | selected_ticket: 5,
          viewed_ticket: 3,
          selected_file: 2,
          viewed_file: 1,
          detail_scroll: 10
      }

      result = State.load_project_without_tickets(state, project_dir)

      assert result.selected_ticket == nil
      assert result.viewed_ticket == nil
      assert result.selected_file == nil
      assert result.viewed_file == nil
      assert result.detail_scroll == 0
    end

    test "loads research files from project directory", %{project_dir: project_dir} do
      File.write!(Path.join(project_dir, "research.md"), "# Research")
      File.write!(Path.join(project_dir, "notes.json"), "{}")
      File.write!(Path.join(project_dir, "other.txt"), "ignored")

      state = State.new()

      result = State.load_project_without_tickets(state, project_dir)

      assert length(result.research_files) == 2
      names = Enum.map(result.research_files, & &1.name)
      assert "research.md" in names
      assert "notes.json" in names
    end
  end

  describe "panel scroll adjustment" do
    test "move_down adjusts scroll when selection exceeds visible area" do
      projects = for i <- 1..20, do: %{id: "project-#{i}"}

      state = %State{
        State.new()
        | projects: projects,
          current_project: 5,
          active_panel: :projects,
          terminal_size: {120, 30},
          panel_scroll: %{projects: 0, tickets: 0, research: 0}
      }

      result = State.move_down(state)

      assert result.current_project == 6
      assert result.panel_scroll.projects >= 0
    end

    test "move_up adjusts scroll when selection goes above visible area" do
      projects = for i <- 1..20, do: %{id: "project-#{i}"}

      state = %State{
        State.new()
        | projects: projects,
          current_project: 1,
          active_panel: :projects,
          terminal_size: {120, 30},
          panel_scroll: %{projects: 5, tickets: 0, research: 0}
      }

      result = State.move_up(state)

      assert result.current_project == 0
      assert result.panel_scroll.projects == 0
    end

    test "scroll adjusts for tickets panel" do
      tickets = for i <- 1..20, do: build_ticket("#{i}")
      data = build_tickets_data(tickets)

      state = %State{
        State.new()
        | data: data,
          selected_ticket: 5,
          active_panel: :tickets,
          terminal_size: {120, 30},
          panel_scroll: %{projects: 0, tickets: 0, research: 0}
      }

      result = State.move_down(state)

      assert result.selected_ticket == 6
      assert result.panel_scroll.tickets >= 0
    end

    test "scroll adjusts for research panel" do
      files = for i <- 1..20, do: %{name: "file-#{i}.md", path: "/file-#{i}.md", type: :markdown}

      state = %State{
        State.new()
        | research_files: files,
          selected_file: 5,
          active_panel: :research,
          terminal_size: {120, 30},
          panel_scroll: %{projects: 0, tickets: 0, research: 0}
      }

      result = State.move_down(state)

      assert result.selected_file == 6
      assert result.panel_scroll.research >= 0
    end
  end

  describe "project CRUD functions" do
    test "delete_project removes current project from list" do
      projects = [%{id: "a", task: "task1"}, %{id: "b", task: "task2"}, %{id: "c", task: "task3"}]
      state = %State{State.new() | projects: projects, current_project: 1}

      result = State.delete_project(state)

      assert length(result.projects) == 2
      assert Enum.at(result.projects, 0).id == "a"
      assert Enum.at(result.projects, 1).id == "c"
    end

    test "delete_project adjusts current_project index when deleting last item" do
      projects = [%{id: "a"}, %{id: "b"}]
      state = %State{State.new() | projects: projects, current_project: 1}

      result = State.delete_project(state)

      assert result.current_project == 0
    end

    test "delete_project handles empty list after deletion" do
      projects = [%{id: "a"}]
      state = %State{State.new() | projects: projects, current_project: 0}

      result = State.delete_project(state)

      assert result.projects == []
      assert result.current_project == 0
    end

    test "update_project_task updates task of current project" do
      projects = [%{id: "a", task: "old task"}, %{id: "b", task: "other"}]
      state = %State{State.new() | projects: projects, current_project: 0}

      result = State.update_project_task(state, "new task")

      assert Enum.at(result.projects, 0).task == "new task"
      assert Enum.at(result.projects, 1).task == "other"
    end

    test "update_project_task truncates long task to 50 chars" do
      projects = [%{id: "a", task: "old"}]
      state = %State{State.new() | projects: projects, current_project: 0}
      long_task = String.duplicate("a", 100)

      result = State.update_project_task(state, long_task)

      assert String.length(Enum.at(result.projects, 0).task) == 50
    end
  end

  describe "nil selection handling" do
    test "move_up with nil selected_ticket selects first ticket" do
      data = build_tickets_data([build_ticket("1"), build_ticket("2")])
      state = %State{State.new() | selected_ticket: nil, active_panel: :tickets, data: data}

      result = State.move_up(state)

      assert result.selected_ticket == 0
    end

    test "move_up with nil selected_ticket and empty tickets does nothing" do
      data = build_tickets_data([])
      state = %State{State.new() | selected_ticket: nil, active_panel: :tickets, data: data}

      result = State.move_up(state)

      assert result.selected_ticket == nil
    end

    test "move_down with nil selected_ticket selects first ticket" do
      data = build_tickets_data([build_ticket("1"), build_ticket("2")])
      state = %State{State.new() | selected_ticket: nil, active_panel: :tickets, data: data}

      result = State.move_down(state)

      assert result.selected_ticket == 0
    end

    test "move_down with nil selected_ticket and empty tickets does nothing" do
      data = build_tickets_data([])
      state = %State{State.new() | selected_ticket: nil, active_panel: :tickets, data: data}

      result = State.move_down(state)

      assert result.selected_ticket == nil
    end

    test "move_up with nil selected_file does nothing" do
      files = [%{name: "a.md", path: "/a.md", type: :markdown}]

      state = %State{
        State.new()
        | selected_file: nil,
          active_panel: :research,
          research_files: files
      }

      result = State.move_up(state)

      assert result.selected_file == nil
    end

    test "move_down with nil selected_file selects first file" do
      files = [%{name: "a.md", path: "/a.md", type: :markdown}]

      state = %State{
        State.new()
        | selected_file: nil,
          active_panel: :research,
          research_files: files
      }

      result = State.move_down(state)

      assert result.selected_file == 0
    end

    test "move_down with nil selected_file and empty files does nothing" do
      state = %State{
        State.new()
        | selected_file: nil,
          active_panel: :research,
          research_files: []
      }

      result = State.move_down(state)

      assert result.selected_file == nil
    end

    test "current_ticket returns nil when selected_ticket is nil" do
      data = build_tickets_data([build_ticket("1")])
      state = %State{State.new() | data: data, selected_ticket: nil}

      assert State.current_ticket(state) == nil
    end

    test "current_research_file returns nil when selected_file is nil" do
      files = [%{name: "a.md", path: "/a.md", type: :markdown}]
      state = %State{State.new() | research_files: files, selected_file: nil}

      assert State.current_research_file(state) == nil
    end

    test "current_research_file returns nil when research_files is empty" do
      state = %State{State.new() | research_files: [], selected_file: 0}

      assert State.current_research_file(state) == nil
    end
  end

  describe "set_active_panel/2" do
    test "sets active panel to tickets and auto-selects first ticket" do
      data = build_tickets_data([build_ticket("1"), build_ticket("2")])
      state = %State{State.new() | data: data, selected_ticket: nil}

      result = State.set_active_panel(state, :tickets)

      assert result.active_panel == :tickets
      assert result.selected_ticket == 0
    end

    test "sets active panel to tickets without auto-select when already selected" do
      data = build_tickets_data([build_ticket("1"), build_ticket("2")])
      state = %State{State.new() | data: data, selected_ticket: 1}

      result = State.set_active_panel(state, :tickets)

      assert result.active_panel == :tickets
      assert result.selected_ticket == 1
    end

    test "sets active panel to research and auto-selects first file" do
      files = [%{name: "a.md", path: "/a.md", type: :markdown}]
      state = %State{State.new() | research_files: files, selected_file: nil}

      result = State.set_active_panel(state, :research)

      assert result.active_panel == :research
      assert result.selected_file == 0
    end

    test "sets active panel to research without auto-select when already selected" do
      files = [%{name: "a.md", path: "/a.md", type: :markdown}]
      state = %State{State.new() | research_files: files, selected_file: 0}

      result = State.set_active_panel(state, :research)

      assert result.active_panel == :research
      assert result.selected_file == 0
    end

    test "sets active panel to projects without auto-selection" do
      state = State.new()

      result = State.set_active_panel(state, :projects)

      assert result.active_panel == :projects
    end

    test "sets active panel to detail without auto-selection" do
      state = State.new()

      result = State.set_active_panel(state, :detail)

      assert result.active_panel == :detail
    end
  end

  describe "next_panel/1 with auto-selection" do
    test "projects to tickets auto-selects first ticket" do
      data = build_tickets_data([build_ticket("1")])
      state = %State{State.new() | data: data, selected_ticket: nil, active_panel: :projects}

      result = State.next_panel(state)

      assert result.active_panel == :tickets
      assert result.selected_ticket == 0
    end

    test "tickets to research auto-selects first file" do
      files = [%{name: "a.md", path: "/a.md", type: :markdown}]

      state = %State{
        State.new()
        | research_files: files,
          selected_file: nil,
          active_panel: :tickets
      }

      result = State.next_panel(state)

      assert result.active_panel == :research
      assert result.selected_file == 0
    end

    test "tickets to research does not auto-select when no files" do
      state = %State{State.new() | research_files: [], selected_file: nil, active_panel: :tickets}

      result = State.next_panel(state)

      assert result.active_panel == :research
      assert result.selected_file == nil
    end
  end

  describe "prev_panel/1 with auto-selection" do
    test "research to tickets auto-selects first ticket" do
      data = build_tickets_data([build_ticket("1")])
      state = %State{State.new() | data: data, selected_ticket: nil, active_panel: :research}

      result = State.prev_panel(state)

      assert result.active_panel == :tickets
      assert result.selected_ticket == 0
    end

    test "detail to research auto-selects first file" do
      files = [%{name: "a.md", path: "/a.md", type: :markdown}]

      state = %State{
        State.new()
        | research_files: files,
          selected_file: nil,
          active_panel: :detail
      }

      result = State.prev_panel(state)

      assert result.active_panel == :research
      assert result.selected_file == 0
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
