defmodule Albedo.TUI.StateTest do
  use ExUnit.Case, async: true

  alias Albedo.Tickets.Ticket
  alias Albedo.TUI.State

  describe "new/1" do
    test "creates a new state with defaults" do
      state = State.new()

      assert state.session_dir == nil
      assert state.data == nil
      assert state.sessions == []
      assert state.current_session == 0
      assert state.selected_ticket == 0
      assert state.active_panel == :sessions
      assert state.mode == :normal
      assert state.quit == false
    end

    test "accepts session_dir option" do
      state = State.new(session_dir: "/tmp/test")

      assert state.session_dir == "/tmp/test"
    end
  end

  describe "move_up/1" do
    test "decrements current_session when in sessions panel" do
      state = %State{State.new() | current_session: 2, active_panel: :sessions}

      result = State.move_up(state)

      assert result.current_session == 1
    end

    test "does not go below 0 for sessions" do
      state = %State{State.new() | current_session: 0, active_panel: :sessions}

      result = State.move_up(state)

      assert result.current_session == 0
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

      assert result.selected_ticket == 0
    end
  end

  describe "move_down/1" do
    test "increments current_session when in sessions panel" do
      sessions = [%{id: "a"}, %{id: "b"}, %{id: "c"}]

      state = %State{
        State.new()
        | current_session: 0,
          active_panel: :sessions,
          sessions: sessions
      }

      result = State.move_down(state)

      assert result.current_session == 1
    end

    test "does not exceed session count" do
      sessions = [%{id: "a"}, %{id: "b"}]

      state = %State{
        State.new()
        | current_session: 1,
          active_panel: :sessions,
          sessions: sessions
      }

      result = State.move_down(state)

      assert result.current_session == 1
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
    test "cycles sessions -> tickets -> detail -> sessions" do
      state = State.new()

      assert state.active_panel == :sessions
      assert State.next_panel(state).active_panel == :tickets
      assert State.next_panel(State.next_panel(state)).active_panel == :detail
      assert State.next_panel(State.next_panel(State.next_panel(state))).active_panel == :sessions
    end
  end

  describe "prev_panel/1" do
    test "cycles sessions -> detail -> tickets -> sessions" do
      state = State.new()

      assert state.active_panel == :sessions
      assert State.prev_panel(state).active_panel == :detail
      assert State.prev_panel(State.prev_panel(state)).active_panel == :tickets
      assert State.prev_panel(State.prev_panel(State.prev_panel(state))).active_panel == :sessions
    end
  end

  describe "current_session/1" do
    test "returns the currently selected session" do
      sessions = [%{id: "a"}, %{id: "b"}]
      state = %State{State.new() | sessions: sessions, current_session: 1}

      assert State.current_session(state) == %{id: "b"}
    end

    test "returns nil when no sessions" do
      state = State.new()

      assert State.current_session(state) == nil
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

  describe "set_message/2 and clear_message/1" do
    test "sets and clears message" do
      state = State.new()

      state = State.set_message(state, "Hello")
      assert state.message == "Hello"

      state = State.clear_message(state)
      assert state.message == nil
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

  describe "visible_tickets/1" do
    test "returns empty list when no data" do
      state = State.new()

      assert State.visible_tickets(state) == []
    end

    test "returns tickets with indices when data exists" do
      ticket1 = build_ticket("1")
      ticket2 = build_ticket("2")
      data = build_tickets_data([ticket1, ticket2])
      state = %State{State.new() | data: data}

      result = State.visible_tickets(state)

      assert length(result) == 2
      assert {^ticket1, 0} = Enum.at(result, 0)
      assert {^ticket2, 1} = Enum.at(result, 1)
    end
  end

  describe "scroll functions" do
    test "scroll_detail_up decrements detail_scroll" do
      state = %State{State.new() | detail_scroll: 5}

      result = State.scroll_detail_up(state)

      assert result.detail_scroll == 4
    end

    test "scroll_detail_up does not go below 0" do
      state = %State{State.new() | detail_scroll: 0}

      result = State.scroll_detail_up(state)

      assert result.detail_scroll == 0
    end

    test "scroll_detail_down increments detail_scroll" do
      state = %State{State.new() | detail_scroll: 0}

      result = State.scroll_detail_down(state)

      assert result.detail_scroll == 1
    end

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

      result = State.enter_input_mode(state, :new_session, "Enter task: ")

      assert result.mode == :input
      assert result.input_mode == :new_session
      assert result.input_prompt == "Enter task: "
      assert result.input_buffer == ""
      assert result.input_cursor == 0
    end

    test "exit_input_mode resets input state" do
      state = %State{
        State.new()
        | mode: :input,
          input_mode: :new_session,
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

      result = State.enter_confirm_mode(state, :delete_session, "Delete session? (y/n)")

      assert result.mode == :confirm
      assert result.confirm_action == :delete_session
      assert result.confirm_message == "Delete session? (y/n)"
    end

    test "exit_confirm_mode resets confirm state" do
      state = %State{
        State.new()
        | mode: :confirm,
          confirm_action: :delete_session,
          confirm_message: "Delete?"
      }

      result = State.exit_confirm_mode(state)

      assert result.mode == :normal
      assert result.confirm_action == nil
      assert result.confirm_message == nil
    end
  end

  describe "load_sessions/2" do
    setup do
      test_dir = Path.join(System.tmp_dir!(), "albedo_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      {:ok, sessions_dir: test_dir}
    end

    test "loads sessions from directory", %{sessions_dir: sessions_dir} do
      session_dir = Path.join(sessions_dir, "test-session")
      File.mkdir_p!(session_dir)

      session_data = %{"state" => "planning", "task" => "Test task description"}
      File.write!(Path.join(session_dir, "session.json"), Jason.encode!(session_data))

      state = State.new()

      result = State.load_sessions(state, sessions_dir)

      assert length(result.sessions) == 1
      assert result.sessions_dir == sessions_dir
      assert hd(result.sessions).id == "test-session"
      assert hd(result.sessions).state == "planning"
      assert hd(result.sessions).task == "Test task description"
    end

    test "returns empty list when directory does not exist", %{sessions_dir: sessions_dir} do
      nonexistent_dir = Path.join(sessions_dir, "nonexistent")
      state = State.new()

      result = State.load_sessions(state, nonexistent_dir)

      assert result.sessions == []
      assert result.sessions_dir == nonexistent_dir
    end

    test "ignores hidden directories", %{sessions_dir: sessions_dir} do
      hidden_dir = Path.join(sessions_dir, ".hidden-session")
      File.mkdir_p!(hidden_dir)
      File.write!(Path.join(hidden_dir, "session.json"), "{}")

      visible_dir = Path.join(sessions_dir, "visible-session")
      File.mkdir_p!(visible_dir)
      File.write!(Path.join(visible_dir, "session.json"), "{}")

      state = State.new()

      result = State.load_sessions(state, sessions_dir)

      assert length(result.sessions) == 1
      assert hd(result.sessions).id == "visible-session"
    end

    test "ignores directories without session.json", %{sessions_dir: sessions_dir} do
      no_session_dir = Path.join(sessions_dir, "no-session")
      File.mkdir_p!(no_session_dir)

      with_session_dir = Path.join(sessions_dir, "with-session")
      File.mkdir_p!(with_session_dir)
      File.write!(Path.join(with_session_dir, "session.json"), "{}")

      state = State.new()

      result = State.load_sessions(state, sessions_dir)

      assert length(result.sessions) == 1
      assert hd(result.sessions).id == "with-session"
    end

    test "sorts sessions in descending order", %{sessions_dir: sessions_dir} do
      for name <- ["aaa-session", "zzz-session", "mmm-session"] do
        dir = Path.join(sessions_dir, name)
        File.mkdir_p!(dir)
        File.write!(Path.join(dir, "session.json"), "{}")
      end

      state = State.new()

      result = State.load_sessions(state, sessions_dir)

      ids = Enum.map(result.sessions, & &1.id)
      assert ids == ["zzz-session", "mmm-session", "aaa-session"]
    end

    test "truncates task to 50 characters", %{sessions_dir: sessions_dir} do
      session_dir = Path.join(sessions_dir, "long-task-session")
      File.mkdir_p!(session_dir)

      long_task = String.duplicate("a", 100)
      session_data = %{"task" => long_task}
      File.write!(Path.join(session_dir, "session.json"), Jason.encode!(session_data))

      state = State.new()

      result = State.load_sessions(state, sessions_dir)

      assert String.length(hd(result.sessions).task) == 50
    end
  end

  describe "load_tickets/2" do
    setup do
      test_dir = Path.join(System.tmp_dir!(), "albedo_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      {:ok, session_dir: test_dir}
    end

    test "loads tickets from session directory", %{session_dir: session_dir} do
      tickets_data = %{
        "session_id" => "test",
        "task_description" => "Test task",
        "tickets" => [
          %{"id" => "1", "title" => "Ticket 1", "status" => "pending"}
        ]
      }

      File.write!(Path.join(session_dir, "tickets.json"), Jason.encode!(tickets_data))

      state = State.new()

      {:ok, result} = State.load_tickets(state, session_dir)

      assert result.session_dir == session_dir
      assert result.selected_ticket == 0
      assert length(result.data.tickets) == 1
    end

    test "returns error when tickets file does not exist", %{session_dir: session_dir} do
      state = State.new()

      result = State.load_tickets(state, session_dir)

      assert {:error, _reason} = result
    end
  end

  describe "session CRUD functions" do
    test "delete_session removes current session from list" do
      sessions = [%{id: "a", task: "task1"}, %{id: "b", task: "task2"}, %{id: "c", task: "task3"}]
      state = %State{State.new() | sessions: sessions, current_session: 1}

      result = State.delete_session(state)

      assert length(result.sessions) == 2
      assert Enum.at(result.sessions, 0).id == "a"
      assert Enum.at(result.sessions, 1).id == "c"
    end

    test "delete_session adjusts current_session index when deleting last item" do
      sessions = [%{id: "a"}, %{id: "b"}]
      state = %State{State.new() | sessions: sessions, current_session: 1}

      result = State.delete_session(state)

      assert result.current_session == 0
    end

    test "delete_session handles empty list after deletion" do
      sessions = [%{id: "a"}]
      state = %State{State.new() | sessions: sessions, current_session: 0}

      result = State.delete_session(state)

      assert result.sessions == []
      assert result.current_session == 0
    end

    test "update_session_task updates task of current session" do
      sessions = [%{id: "a", task: "old task"}, %{id: "b", task: "other"}]
      state = %State{State.new() | sessions: sessions, current_session: 0}

      result = State.update_session_task(state, "new task")

      assert Enum.at(result.sessions, 0).task == "new task"
      assert Enum.at(result.sessions, 1).task == "other"
    end

    test "update_session_task truncates long task to 50 chars" do
      sessions = [%{id: "a", task: "old"}]
      state = %State{State.new() | sessions: sessions, current_session: 0}
      long_task = String.duplicate("a", 100)

      result = State.update_session_task(state, long_task)

      assert String.length(Enum.at(result.sessions, 0).task) == 50
    end
  end

  defp build_tickets_data(tickets) do
    %{
      session_id: "test-session",
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
