defmodule Albedo.TUI do
  @moduledoc """
  Terminal User Interface for Albedo.
  Provides a lazygit-inspired panel-based interface for managing projects and tickets.

  Uses a pure Elixir approach with raw terminal mode and ANSI escape codes.
  """

  alias Albedo.{Config, Project, Tickets}
  alias Albedo.TUI.{Renderer, State, Terminal}

  @doc """
  Starts the TUI application.
  """
  def start(opts \\ []) do
    config = Config.load!()
    projects_dir = Config.projects_dir(config)

    state =
      State.new(opts)
      |> State.load_projects(projects_dir)

    case Terminal.enable_raw_mode() do
      {:ok, old_settings} ->
        try do
          Terminal.enter_alternate_screen()
          Terminal.hide_cursor()
          run_loop(state, projects_dir)
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

  defp run_loop(%State{quit: true}, _projects_dir), do: :ok

  defp run_loop(%State{} = state, projects_dir) do
    Renderer.render(state)

    case Terminal.read_char() do
      :ctrl_c ->
        :ok

      :ctrl_d ->
        :ok

      input ->
        state
        |> handle_input(input, projects_dir)
        |> run_loop(projects_dir)
    end
  end

  defp handle_input(%State{mode: :edit} = state, input, projects_dir) do
    dispatch_edit_input(state, input, projects_dir)
  end

  defp handle_input(%State{mode: :input} = state, input, projects_dir) do
    dispatch_input_mode(state, input, projects_dir)
  end

  defp handle_input(%State{mode: :confirm} = state, input, projects_dir) do
    dispatch_confirm_mode(state, input, projects_dir)
  end

  defp handle_input(%State{mode: :help} = state, input, _projects_dir) do
    dispatch_help_mode(state, input)
  end

  defp handle_input(state, input, projects_dir) do
    state
    |> dispatch_input(input, projects_dir)
    |> State.clear_message()
  end

  defp dispatch_edit_input(state, :escape, _projects_dir) do
    State.exit_edit_mode(state)
    |> State.set_message("Edit cancelled")
  end

  defp dispatch_edit_input(state, :tab, _projects_dir) do
    save_current_field(state)
    |> State.next_edit_field()
  end

  defp dispatch_edit_input(state, :shift_tab, _projects_dir) do
    save_current_field(state)
    |> State.prev_edit_field()
  end

  defp dispatch_edit_input(state, :enter, projects_dir) do
    save_and_exit_edit(state, projects_dir)
  end

  defp dispatch_edit_input(state, :backspace, _projects_dir) do
    State.edit_delete_char(state)
  end

  defp dispatch_edit_input(state, :left, _projects_dir) do
    State.edit_move_cursor_left(state)
  end

  defp dispatch_edit_input(state, :right, _projects_dir) do
    State.edit_move_cursor_right(state)
  end

  defp dispatch_edit_input(state, :home, _projects_dir) do
    State.edit_cursor_home(state)
  end

  defp dispatch_edit_input(state, :end, _projects_dir) do
    State.edit_cursor_end(state)
  end

  defp dispatch_edit_input(state, {:char, char}, _projects_dir) do
    State.edit_insert_char(state, char)
  end

  defp dispatch_edit_input(state, _, _projects_dir), do: state

  defp dispatch_input(state, {:char, char}, projects_dir) do
    handle_char(state, char, projects_dir)
  end

  defp dispatch_input(state, :down, _projects_dir), do: State.move_down(state)
  defp dispatch_input(state, :up, _projects_dir), do: State.move_up(state)
  defp dispatch_input(state, :right, _projects_dir), do: State.next_panel(state)
  defp dispatch_input(state, :left, _projects_dir), do: State.prev_panel(state)
  defp dispatch_input(state, :tab, _projects_dir), do: State.next_panel(state)
  defp dispatch_input(state, :shift_tab, _projects_dir), do: State.prev_panel(state)
  defp dispatch_input(state, :enter, projects_dir), do: handle_enter(state, projects_dir)
  defp dispatch_input(state, _, _projects_dir), do: state

  defp handle_char(state, "q", _projects_dir), do: State.quit(state)
  defp handle_char(state, "Q", _projects_dir), do: State.quit(state)
  defp handle_char(state, "j", _projects_dir), do: State.move_down(state)
  defp handle_char(state, "k", _projects_dir), do: State.move_up(state)
  defp handle_char(state, "l", _projects_dir), do: State.next_panel(state)
  defp handle_char(state, "h", _projects_dir), do: State.prev_panel(state)
  defp handle_char(state, "s", _projects_dir), do: handle_start(state)
  defp handle_char(state, "d", _projects_dir), do: handle_done(state)
  defp handle_char(state, "r", _projects_dir), do: handle_reset(state)
  defp handle_char(state, "R", projects_dir), do: handle_refresh(state, projects_dir)
  defp handle_char(state, "a", _projects_dir), do: handle_add(state)
  defp handle_char(state, "n", _projects_dir), do: handle_new_project(state)
  defp handle_char(state, "e", _projects_dir), do: handle_edit(state)
  defp handle_char(state, "x", _projects_dir), do: handle_delete(state)
  defp handle_char(state, "X", _projects_dir), do: handle_delete(state)
  defp handle_char(state, "?", _projects_dir), do: State.enter_help_mode(state)
  defp handle_char(state, _, _projects_dir), do: state

  defp dispatch_help_mode(state, :escape), do: State.exit_help_mode(state)
  defp dispatch_help_mode(state, :enter), do: State.exit_help_mode(state)
  defp dispatch_help_mode(state, {:char, "q"}), do: State.exit_help_mode(state)
  defp dispatch_help_mode(state, {:char, "?"}), do: State.exit_help_mode(state)
  defp dispatch_help_mode(state, _), do: state

  defp handle_enter(%State{active_panel: :projects} = state, projects_dir) do
    case State.current_project(state) do
      nil ->
        State.set_message(state, "No project selected")

      project ->
        project_path = Path.join(projects_dir, project.id)

        case State.load_tickets(state, project_path) do
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

  defp handle_enter(state, _projects_dir), do: state

  defp handle_start(%State{data: nil} = state) do
    State.set_message(state, "No project loaded")
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
    State.set_message(state, "No project loaded")
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
    State.set_message(state, "No project loaded")
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

  defp handle_refresh(state, projects_dir) do
    state
    |> State.load_projects(projects_dir)
    |> State.set_message("Refreshed projects")
  end

  defp save_and_update(%State{project_dir: project_dir} = state, updated_data, message) do
    case Tickets.save(project_dir, updated_data) do
      :ok ->
        state
        |> Map.put(:data, updated_data)
        |> State.set_message(message)

      {:error, reason} ->
        State.set_message(state, "Save failed: #{inspect(reason)}")
    end
  end

  defp handle_add_ticket(%State{data: nil} = state) do
    State.set_message(state, "Load a project first (Enter on projects panel)")
  end

  defp handle_add_ticket(%State{data: data, project_dir: project_dir} = state) do
    attrs = %{title: "New ticket", type: :feature, priority: :medium}

    case Tickets.add(data, attrs) do
      {:ok, updated_data, ticket} ->
        case Tickets.save(project_dir, updated_data) do
          :ok ->
            new_idx = length(updated_data.tickets) - 1

            %{state | data: updated_data, selected_ticket: new_idx}
            |> State.set_message("Added ticket ##{ticket.id}. Edit with 'e' to change details.")

          {:error, reason} ->
            State.set_message(state, "Failed to save ticket: #{inspect(reason)}")
        end
    end
  end

  defp enter_edit_mode(%State{data: nil} = state) do
    State.set_message(state, "No project loaded")
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

    case Tickets.edit(data, ticket.id, changes) do
      {:ok, updated_data, _updated_ticket} ->
        %{state | data: updated_data}

      {:error, :not_found} ->
        state
    end
  end

  defp save_and_exit_edit(%State{data: data, project_dir: project_dir} = state, _projects_dir) do
    ticket = State.current_ticket(state)
    changes = State.get_edit_changes(state)

    case Tickets.edit(data, ticket.id, changes) do
      {:ok, updated_data, _updated_ticket} ->
        case Tickets.save(project_dir, updated_data) do
          :ok ->
            %{state | data: updated_data}
            |> State.exit_edit_mode()
            |> State.set_message("Ticket saved")

          {:error, reason} ->
            state
            |> State.exit_edit_mode()
            |> State.set_message("Save failed: #{inspect(reason)}")
        end

      {:error, :not_found} ->
        state
        |> State.exit_edit_mode()
        |> State.set_message("Ticket not found")
    end
  end

  defp handle_delete_ticket(%State{data: nil} = state) do
    State.set_message(state, "No project loaded")
  end

  defp handle_delete_ticket(%State{data: data, project_dir: project_dir} = state) do
    with ticket when not is_nil(ticket) <- State.current_ticket(state),
         {:ok, updated_data, _deleted} <- Tickets.delete(data, ticket.id),
         :ok <- Tickets.save(project_dir, updated_data) do
      new_idx = min(state.selected_ticket, max(0, length(updated_data.tickets) - 1))

      %{state | data: updated_data, selected_ticket: new_idx}
      |> State.set_message("Deleted ticket ##{ticket.id}")
    else
      nil -> State.set_message(state, "No ticket selected")
      {:error, :not_found} -> State.set_message(state, "Ticket not found")
      {:error, reason} -> State.set_message(state, "Failed to save: #{inspect(reason)}")
    end
  end

  defp dispatch_input_mode(state, :escape, _projects_dir) do
    State.exit_input_mode(state)
    |> State.set_message("Cancelled")
  end

  defp dispatch_input_mode(state, :enter, projects_dir) do
    handle_input_submit(state, projects_dir)
  end

  defp dispatch_input_mode(state, :backspace, _projects_dir) do
    State.input_delete_char(state)
  end

  defp dispatch_input_mode(state, :left, _projects_dir) do
    State.input_move_cursor_left(state)
  end

  defp dispatch_input_mode(state, :right, _projects_dir) do
    State.input_move_cursor_right(state)
  end

  defp dispatch_input_mode(state, {:char, char}, _projects_dir) do
    State.input_insert_char(state, char)
  end

  defp dispatch_input_mode(state, _, _projects_dir), do: state

  defp handle_input_submit(
         %State{input_mode: :new_project, input_buffer: task} = state,
         projects_dir
       ) do
    if String.trim(task) == "" do
      State.exit_input_mode(state)
      |> State.set_message("Project task cannot be empty")
    else
      create_new_project(state, task, projects_dir)
    end
  end

  defp handle_input_submit(
         %State{input_mode: :edit_project, input_buffer: task} = state,
         projects_dir
       ) do
    if String.trim(task) == "" do
      State.exit_input_mode(state)
      |> State.set_message("Project task cannot be empty")
    else
      save_project_task(state, task, projects_dir)
    end
  end

  defp handle_input_submit(state, _projects_dir) do
    State.exit_input_mode(state)
  end

  defp dispatch_confirm_mode(state, {:char, "y"}, projects_dir) do
    execute_confirmed_action(state, projects_dir)
  end

  defp dispatch_confirm_mode(state, {:char, "Y"}, projects_dir) do
    execute_confirmed_action(state, projects_dir)
  end

  defp dispatch_confirm_mode(state, {:char, "n"}, _projects_dir) do
    State.exit_confirm_mode(state)
    |> State.set_message("Cancelled")
  end

  defp dispatch_confirm_mode(state, {:char, "N"}, _projects_dir) do
    State.exit_confirm_mode(state)
    |> State.set_message("Cancelled")
  end

  defp dispatch_confirm_mode(state, :escape, _projects_dir) do
    State.exit_confirm_mode(state)
    |> State.set_message("Cancelled")
  end

  defp dispatch_confirm_mode(state, _, _projects_dir), do: state

  defp execute_confirmed_action(%State{confirm_action: :delete_project} = state, projects_dir) do
    delete_project(state, projects_dir)
  end

  defp execute_confirmed_action(state, _projects_dir) do
    State.exit_confirm_mode(state)
  end

  defp handle_new_project(%State{active_panel: :projects} = state) do
    State.enter_input_mode(state, :new_project, "New project task: ")
  end

  defp handle_new_project(state) do
    State.set_message(state, "Switch to projects panel to create new project")
  end

  defp handle_add(%State{active_panel: :projects} = state) do
    State.enter_input_mode(state, :new_project, "New project task: ")
  end

  defp handle_add(%State{active_panel: :tickets} = state) do
    handle_add_ticket(state)
  end

  defp handle_add(state), do: state

  defp handle_edit(%State{active_panel: :projects} = state) do
    case State.current_project(state) do
      nil ->
        State.set_message(state, "No project selected")

      project ->
        state
        |> State.enter_input_mode(:edit_project, "Edit task: ")
        |> Map.put(:input_buffer, project.task)
        |> Map.put(:input_cursor, String.length(project.task))
    end
  end

  defp handle_edit(%State{active_panel: :tickets} = state) do
    enter_edit_mode(state)
  end

  defp handle_edit(state), do: state

  defp handle_delete(%State{active_panel: :projects} = state) do
    case State.current_project(state) do
      nil ->
        State.set_message(state, "No project selected")

      project ->
        State.enter_confirm_mode(
          state,
          :delete_project,
          "Delete project '#{project.id}'? (y/n)"
        )
    end
  end

  defp handle_delete(%State{active_panel: :tickets} = state) do
    handle_delete_ticket(state)
  end

  defp handle_delete(state), do: state

  defp create_new_project(state, task, projects_dir) do
    project_state = Project.State.new(".", task)

    case Project.State.save(project_state) do
      :ok ->
        state
        |> State.exit_input_mode()
        |> State.load_projects(projects_dir)
        |> Map.put(:current_project, 0)
        |> State.set_message("Created project: #{project_state.id}")

      {:error, reason} ->
        state
        |> State.exit_input_mode()
        |> State.set_message("Failed to create project: #{inspect(reason)}")
    end
  end

  defp save_project_task(state, task, projects_dir) do
    case State.current_project(state) do
      nil ->
        state
        |> State.exit_input_mode()
        |> State.set_message("No project selected")

      project ->
        project_path = Path.join(projects_dir, project.id)
        project_file = Path.join(project_path, "project.json")

        with {:ok, content} <- File.read(project_file),
             {:ok, data} <- Jason.decode(content) do
          updated_data = Map.put(data, "task", task)

          case File.write(project_file, Jason.encode!(updated_data, pretty: true)) do
            :ok ->
              state
              |> State.exit_input_mode()
              |> State.update_project_task(task)
              |> State.set_message("Updated project task")

            {:error, reason} ->
              state
              |> State.exit_input_mode()
              |> State.set_message("Failed to save: #{inspect(reason)}")
          end
        else
          {:error, reason} ->
            state
            |> State.exit_input_mode()
            |> State.set_message("Failed to load project: #{inspect(reason)}")
        end
    end
  end

  defp delete_project(state, projects_dir) do
    case State.current_project(state) do
      nil ->
        state
        |> State.exit_confirm_mode()
        |> State.set_message("No project selected")

      project ->
        project_path = Path.join(projects_dir, project.id)

        case File.rm_rf(project_path) do
          {:ok, _} ->
            state
            |> State.exit_confirm_mode()
            |> State.delete_project()
            |> State.set_message("Deleted project: #{project.id}")

          {:error, reason, _} ->
            state
            |> State.exit_confirm_mode()
            |> State.set_message("Failed to delete: #{inspect(reason)}")
        end
    end
  end
end
