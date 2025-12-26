defmodule Albedo.TUI do
  @moduledoc """
  Terminal User Interface for Albedo.
  Provides a lazygit-inspired panel-based interface for managing sessions and tickets.

  Uses a pure Elixir approach with raw terminal mode and ANSI escape codes.
  """

  alias Albedo.{Config, Tickets}
  alias Albedo.TUI.{Renderer, State, Terminal}

  @doc """
  Starts the TUI application.
  """
  def start(opts \\ []) do
    config = Config.load!()
    sessions_dir = Config.session_dir(config)

    state =
      State.new(opts)
      |> State.load_sessions(sessions_dir)

    case Terminal.enable_raw_mode() do
      {:ok, old_settings} ->
        try do
          Terminal.enter_alternate_screen()
          Terminal.hide_cursor()
          run_loop(state, sessions_dir)
        after
          cleanup(old_settings)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup(old_settings) do
    Terminal.show_cursor()
    Terminal.exit_alternate_screen()
    Terminal.restore_mode(old_settings)
  end

  defp run_loop(%State{quit: true}, _sessions_dir), do: :ok

  defp run_loop(%State{} = state, sessions_dir) do
    Renderer.render(state)

    case Terminal.read_char() do
      :ctrl_c ->
        :ok

      :ctrl_d ->
        :ok

      input ->
        state
        |> handle_input(input, sessions_dir)
        |> run_loop(sessions_dir)
    end
  end

  defp handle_input(%State{mode: :edit} = state, input, sessions_dir) do
    dispatch_edit_input(state, input, sessions_dir)
  end

  defp handle_input(%State{mode: :input} = state, input, sessions_dir) do
    dispatch_input_mode(state, input, sessions_dir)
  end

  defp handle_input(%State{mode: :confirm} = state, input, sessions_dir) do
    dispatch_confirm_mode(state, input, sessions_dir)
  end

  defp handle_input(state, input, sessions_dir) do
    state
    |> dispatch_input(input, sessions_dir)
    |> State.clear_message()
  end

  defp dispatch_edit_input(state, :escape, _sessions_dir) do
    State.exit_edit_mode(state)
    |> State.set_message("Edit cancelled")
  end

  defp dispatch_edit_input(state, :tab, _sessions_dir) do
    save_current_field(state)
    |> State.next_edit_field()
  end

  defp dispatch_edit_input(state, :shift_tab, _sessions_dir) do
    save_current_field(state)
    |> State.prev_edit_field()
  end

  defp dispatch_edit_input(state, :enter, sessions_dir) do
    save_and_exit_edit(state, sessions_dir)
  end

  defp dispatch_edit_input(state, :backspace, _sessions_dir) do
    State.edit_delete_char(state)
  end

  defp dispatch_edit_input(state, :left, _sessions_dir) do
    State.edit_move_cursor_left(state)
  end

  defp dispatch_edit_input(state, :right, _sessions_dir) do
    State.edit_move_cursor_right(state)
  end

  defp dispatch_edit_input(state, :home, _sessions_dir) do
    State.edit_cursor_home(state)
  end

  defp dispatch_edit_input(state, :end, _sessions_dir) do
    State.edit_cursor_end(state)
  end

  defp dispatch_edit_input(state, {:char, char}, _sessions_dir) do
    State.edit_insert_char(state, char)
  end

  defp dispatch_edit_input(state, _, _sessions_dir), do: state

  defp dispatch_input(state, {:char, char}, sessions_dir) do
    handle_char(state, char, sessions_dir)
  end

  defp dispatch_input(state, :down, _sessions_dir), do: State.move_down(state)
  defp dispatch_input(state, :up, _sessions_dir), do: State.move_up(state)
  defp dispatch_input(state, :right, _sessions_dir), do: State.next_panel(state)
  defp dispatch_input(state, :left, _sessions_dir), do: State.prev_panel(state)
  defp dispatch_input(state, :tab, _sessions_dir), do: State.next_panel(state)
  defp dispatch_input(state, :shift_tab, _sessions_dir), do: State.prev_panel(state)
  defp dispatch_input(state, :enter, sessions_dir), do: handle_enter(state, sessions_dir)
  defp dispatch_input(state, _, _sessions_dir), do: state

  defp handle_char(state, "q", _sessions_dir), do: State.quit(state)
  defp handle_char(state, "Q", _sessions_dir), do: State.quit(state)
  defp handle_char(state, "j", _sessions_dir), do: State.move_down(state)
  defp handle_char(state, "k", _sessions_dir), do: State.move_up(state)
  defp handle_char(state, "l", _sessions_dir), do: State.next_panel(state)
  defp handle_char(state, "h", _sessions_dir), do: State.prev_panel(state)
  defp handle_char(state, "s", _sessions_dir), do: handle_start(state)
  defp handle_char(state, "d", _sessions_dir), do: handle_done(state)
  defp handle_char(state, "r", _sessions_dir), do: handle_reset(state)
  defp handle_char(state, "R", sessions_dir), do: handle_refresh(state, sessions_dir)
  defp handle_char(state, "a", _sessions_dir), do: handle_add(state)
  defp handle_char(state, "n", _sessions_dir), do: handle_new_session(state)
  defp handle_char(state, "e", _sessions_dir), do: handle_edit(state)
  defp handle_char(state, "x", _sessions_dir), do: handle_delete(state)
  defp handle_char(state, "X", _sessions_dir), do: handle_delete(state)
  defp handle_char(state, _, _sessions_dir), do: state

  defp handle_enter(%State{active_panel: :sessions} = state, sessions_dir) do
    case State.current_session(state) do
      nil ->
        State.set_message(state, "No session selected")

      session ->
        session_path = Path.join(sessions_dir, session.id)

        case State.load_tickets(state, session_path) do
          {:ok, new_state} ->
            new_state
            |> State.set_message("Loaded #{length(new_state.data.tickets)} tickets")
            |> Map.put(:active_panel, :tickets)

          {:error, :not_found} ->
            State.set_message(state, "No tickets.json found")

          {:error, reason} ->
            State.set_message(state, "Error: #{inspect(reason)}")
        end
    end
  end

  defp handle_enter(state, _sessions_dir), do: state

  defp handle_start(%State{data: nil} = state) do
    State.set_message(state, "No session loaded")
  end

  defp handle_start(%State{data: data} = state) do
    case State.current_ticket(state) do
      nil ->
        State.set_message(state, "No ticket selected")

      ticket ->
        case Tickets.start(data, ticket.id) do
          {:ok, updated_data, _ticket} ->
            save_and_update(state, updated_data, "Ticket ##{ticket.id} started")

          {:error, :not_found} ->
            State.set_message(state, "Ticket not found")
        end
    end
  end

  defp handle_done(%State{data: nil} = state) do
    State.set_message(state, "No session loaded")
  end

  defp handle_done(%State{data: data} = state) do
    case State.current_ticket(state) do
      nil ->
        State.set_message(state, "No ticket selected")

      ticket ->
        case Tickets.complete(data, ticket.id) do
          {:ok, updated_data, _ticket} ->
            save_and_update(state, updated_data, "Ticket ##{ticket.id} completed")

          {:error, :not_found} ->
            State.set_message(state, "Ticket not found")
        end
    end
  end

  defp handle_reset(%State{data: nil} = state) do
    State.set_message(state, "No session loaded")
  end

  defp handle_reset(%State{data: data} = state) do
    case State.current_ticket(state) do
      nil ->
        State.set_message(state, "No ticket selected")

      ticket ->
        case Tickets.reset(data, ticket.id) do
          {:ok, updated_data, _ticket} ->
            save_and_update(state, updated_data, "Ticket ##{ticket.id} reset")

          {:error, :not_found} ->
            State.set_message(state, "Ticket not found")
        end
    end
  end

  defp handle_refresh(state, sessions_dir) do
    state
    |> State.load_sessions(sessions_dir)
    |> State.set_message("Refreshed sessions")
  end

  defp save_and_update(%State{session_dir: session_dir} = state, updated_data, message) do
    case Tickets.save(session_dir, updated_data) do
      :ok ->
        state
        |> Map.put(:data, updated_data)
        |> State.set_message(message)

      {:error, reason} ->
        State.set_message(state, "Save failed: #{inspect(reason)}")
    end
  end

  defp handle_add_ticket(%State{data: nil} = state) do
    State.set_message(state, "Load a session first (Enter on sessions panel)")
  end

  defp handle_add_ticket(%State{data: data, session_dir: session_dir} = state) do
    next_id = next_ticket_id(data.tickets)

    new_ticket =
      Tickets.Ticket.new(%{
        id: next_id,
        title: "New ticket #{next_id}",
        type: :feature,
        priority: :medium
      })

    updated_tickets = data.tickets ++ [new_ticket]
    updated_data = %{data | tickets: updated_tickets}

    case Tickets.save(session_dir, updated_data) do
      :ok ->
        new_idx = length(updated_tickets) - 1

        %{state | data: updated_data, selected_ticket: new_idx}
        |> State.set_message("Added ticket ##{next_id}. Edit with 'e' to change details.")

      {:error, reason} ->
        State.set_message(state, "Failed to add ticket: #{inspect(reason)}")
    end
  end

  defp next_ticket_id(tickets) do
    max_id =
      tickets
      |> Enum.map(& &1.id)
      |> Enum.map(&parse_ticket_id/1)
      |> Enum.max(fn -> 0 end)

    to_string(max_id + 1)
  end

  defp parse_ticket_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, _} -> num
      :error -> 0
    end
  end

  defp parse_ticket_id(_), do: 0

  defp enter_edit_mode(%State{data: nil} = state) do
    State.set_message(state, "No session loaded")
  end

  defp enter_edit_mode(%State{} = state) do
    case State.current_ticket(state) do
      nil ->
        State.set_message(state, "No ticket selected")

      _ticket ->
        State.enter_edit_mode(state)
    end
  end

  defp save_current_field(%State{data: data} = state) do
    ticket = State.current_ticket(state)
    changes = State.get_edit_changes(state)
    updated_ticket = Tickets.Ticket.edit(ticket, changes)

    updated_tickets =
      Enum.map(data.tickets, fn t ->
        if t.id == ticket.id, do: updated_ticket, else: t
      end)

    updated_data = %{data | tickets: updated_tickets}
    %{state | data: updated_data}
  end

  defp save_and_exit_edit(%State{session_dir: session_dir} = state, _sessions_dir) do
    state = save_current_field(state)

    case Tickets.save(session_dir, state.data) do
      :ok ->
        state
        |> State.exit_edit_mode()
        |> State.set_message("Ticket saved")

      {:error, reason} ->
        state
        |> State.exit_edit_mode()
        |> State.set_message("Save failed: #{inspect(reason)}")
    end
  end

  defp handle_delete_ticket(%State{data: nil} = state) do
    State.set_message(state, "No session loaded")
  end

  defp handle_delete_ticket(%State{data: data, session_dir: session_dir} = state) do
    case State.current_ticket(state) do
      nil ->
        State.set_message(state, "No ticket selected")

      ticket ->
        updated_tickets = Enum.reject(data.tickets, &(&1.id == ticket.id))
        updated_data = %{data | tickets: updated_tickets}

        case Tickets.save(session_dir, updated_data) do
          :ok ->
            new_idx = min(state.selected_ticket, max(0, length(updated_tickets) - 1))

            %{state | data: updated_data, selected_ticket: new_idx}
            |> State.set_message("Deleted ticket ##{ticket.id}")

          {:error, reason} ->
            State.set_message(state, "Failed to delete: #{inspect(reason)}")
        end
    end
  end

  defp dispatch_input_mode(state, :escape, _sessions_dir) do
    State.exit_input_mode(state)
    |> State.set_message("Cancelled")
  end

  defp dispatch_input_mode(state, :enter, sessions_dir) do
    handle_input_submit(state, sessions_dir)
  end

  defp dispatch_input_mode(state, :backspace, _sessions_dir) do
    State.input_delete_char(state)
  end

  defp dispatch_input_mode(state, :left, _sessions_dir) do
    State.input_move_cursor_left(state)
  end

  defp dispatch_input_mode(state, :right, _sessions_dir) do
    State.input_move_cursor_right(state)
  end

  defp dispatch_input_mode(state, {:char, char}, _sessions_dir) do
    State.input_insert_char(state, char)
  end

  defp dispatch_input_mode(state, _, _sessions_dir), do: state

  defp handle_input_submit(
         %State{input_mode: :new_session, input_buffer: task} = state,
         sessions_dir
       ) do
    if String.trim(task) == "" do
      State.exit_input_mode(state)
      |> State.set_message("Session task cannot be empty")
    else
      create_new_session(state, task, sessions_dir)
    end
  end

  defp handle_input_submit(
         %State{input_mode: :edit_session, input_buffer: task} = state,
         sessions_dir
       ) do
    if String.trim(task) == "" do
      State.exit_input_mode(state)
      |> State.set_message("Session task cannot be empty")
    else
      save_session_task(state, task, sessions_dir)
    end
  end

  defp handle_input_submit(state, _sessions_dir) do
    State.exit_input_mode(state)
  end

  defp dispatch_confirm_mode(state, {:char, "y"}, sessions_dir) do
    execute_confirmed_action(state, sessions_dir)
  end

  defp dispatch_confirm_mode(state, {:char, "Y"}, sessions_dir) do
    execute_confirmed_action(state, sessions_dir)
  end

  defp dispatch_confirm_mode(state, {:char, "n"}, _sessions_dir) do
    State.exit_confirm_mode(state)
    |> State.set_message("Cancelled")
  end

  defp dispatch_confirm_mode(state, {:char, "N"}, _sessions_dir) do
    State.exit_confirm_mode(state)
    |> State.set_message("Cancelled")
  end

  defp dispatch_confirm_mode(state, :escape, _sessions_dir) do
    State.exit_confirm_mode(state)
    |> State.set_message("Cancelled")
  end

  defp dispatch_confirm_mode(state, _, _sessions_dir), do: state

  defp execute_confirmed_action(%State{confirm_action: :delete_session} = state, sessions_dir) do
    delete_session(state, sessions_dir)
  end

  defp execute_confirmed_action(state, _sessions_dir) do
    State.exit_confirm_mode(state)
  end

  defp handle_new_session(%State{active_panel: :sessions} = state) do
    State.enter_input_mode(state, :new_session, "New session task: ")
  end

  defp handle_new_session(state) do
    State.set_message(state, "Switch to sessions panel to create new session")
  end

  defp handle_add(%State{active_panel: :sessions} = state) do
    State.enter_input_mode(state, :new_session, "New session task: ")
  end

  defp handle_add(%State{active_panel: :tickets} = state) do
    handle_add_ticket(state)
  end

  defp handle_add(state), do: state

  defp handle_edit(%State{active_panel: :sessions} = state) do
    case State.current_session(state) do
      nil ->
        State.set_message(state, "No session selected")

      session ->
        state
        |> State.enter_input_mode(:edit_session, "Edit task: ")
        |> Map.put(:input_buffer, session.task)
        |> Map.put(:input_cursor, String.length(session.task))
    end
  end

  defp handle_edit(%State{active_panel: :tickets} = state) do
    enter_edit_mode(state)
  end

  defp handle_edit(state), do: state

  defp handle_delete(%State{active_panel: :sessions} = state) do
    case State.current_session(state) do
      nil ->
        State.set_message(state, "No session selected")

      session ->
        State.enter_confirm_mode(
          state,
          :delete_session,
          "Delete session '#{session.id}'? (y/n)"
        )
    end
  end

  defp handle_delete(%State{active_panel: :tickets} = state) do
    handle_delete_ticket(state)
  end

  defp handle_delete(state), do: state

  defp create_new_session(state, task, sessions_dir) do
    session_state = Albedo.Session.State.new(".", task)

    case Albedo.Session.State.save(session_state) do
      :ok ->
        state
        |> State.exit_input_mode()
        |> State.load_sessions(sessions_dir)
        |> Map.put(:current_session, 0)
        |> State.set_message("Created session: #{session_state.id}")

      {:error, reason} ->
        state
        |> State.exit_input_mode()
        |> State.set_message("Failed to create session: #{inspect(reason)}")
    end
  end

  defp save_session_task(state, task, sessions_dir) do
    case State.current_session(state) do
      nil ->
        state
        |> State.exit_input_mode()
        |> State.set_message("No session selected")

      session ->
        session_path = Path.join(sessions_dir, session.id)
        session_file = Path.join(session_path, "session.json")

        with {:ok, content} <- File.read(session_file),
             {:ok, data} <- Jason.decode(content) do
          updated_data = Map.put(data, "task", task)

          case File.write(session_file, Jason.encode!(updated_data, pretty: true)) do
            :ok ->
              state
              |> State.exit_input_mode()
              |> State.update_session_task(task)
              |> State.set_message("Updated session task")

            {:error, reason} ->
              state
              |> State.exit_input_mode()
              |> State.set_message("Failed to save: #{inspect(reason)}")
          end
        else
          {:error, reason} ->
            state
            |> State.exit_input_mode()
            |> State.set_message("Failed to load session: #{inspect(reason)}")
        end
    end
  end

  defp delete_session(state, sessions_dir) do
    case State.current_session(state) do
      nil ->
        state
        |> State.exit_confirm_mode()
        |> State.set_message("No session selected")

      session ->
        session_path = Path.join(sessions_dir, session.id)

        case File.rm_rf(session_path) do
          {:ok, _} ->
            state
            |> State.exit_confirm_mode()
            |> State.delete_session()
            |> State.set_message("Deleted session: #{session.id}")

          {:error, reason, _} ->
            state
            |> State.exit_confirm_mode()
            |> State.set_message("Failed to delete: #{inspect(reason)}")
        end
    end
  end
end
