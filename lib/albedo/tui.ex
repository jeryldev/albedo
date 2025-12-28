defmodule Albedo.TUI do
  @moduledoc """
  Terminal User Interface for Albedo.
  Provides a lazygit-inspired panel-based interface for managing projects and tickets.

  Uses a pure Elixir approach with raw terminal mode and ANSI escape codes.
  """

  alias Albedo.{Config, Project, Tickets}
  alias Albedo.TUI.{LogHandler, Renderer, State, Terminal}
  alias Albedo.Utils.Id

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
          input_pid = start_input_reader()
          run_loop(state, projects_dir, input_pid)
        after
          cleanup(old_settings)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup(old_settings) do
    LogHandler.uninstall()
    Terminal.show_cursor()
    Terminal.exit_alternate_screen()
    Terminal.restore_mode(old_settings)
  end

  defp run_loop(%State{quit: true}, _projects_dir, _input_pid), do: :ok

  defp run_loop(%State{} = state, projects_dir, input_pid) do
    Renderer.render(state)

    receive do
      {:input, :ctrl_c} ->
        send(input_pid, :stop)
        :ok

      {:input, :ctrl_d} ->
        send(input_pid, :stop)
        :ok

      {:input, input} ->
        state
        |> handle_input(input, projects_dir)
        |> run_loop(projects_dir, input_pid)

      {:operation_complete, result} ->
        state
        |> handle_operation_complete(result, projects_dir)
        |> run_loop(projects_dir, input_pid)

      {:operation_progress, message} ->
        state
        |> handle_operation_progress(message)
        |> run_loop(projects_dir, input_pid)

      {:agent_progress, current, total, agent_name} ->
        state
        |> handle_agent_progress(current, total, agent_name)
        |> run_loop(projects_dir, input_pid)

      {:log_message, message} ->
        state
        |> handle_log_message(message)
        |> run_loop(projects_dir, input_pid)
    end
  end

  defp start_input_reader do
    parent = self()

    spawn_link(fn ->
      input_reader_loop(parent)
    end)
  end

  defp input_reader_loop(parent) do
    receive do
      :stop -> :ok
    after
      0 ->
        char = Terminal.read_char()
        send(parent, {:input, char})
        input_reader_loop(parent)
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

  defp handle_input(%State{mode: :modal} = state, input, projects_dir) do
    dispatch_modal_mode(state, input, projects_dir)
  end

  defp handle_input(state, input, projects_dir) do
    dispatch_input(state, input, projects_dir)
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
  defp handle_char(state, "n", _projects_dir), do: handle_new(state)
  defp handle_char(state, "p", _projects_dir), do: handle_plan(state)
  defp handle_char(state, "a", _projects_dir), do: handle_analyze(state)
  defp handle_char(state, "e", _projects_dir), do: handle_edit(state)
  defp handle_char(state, "x", _projects_dir), do: handle_delete(state)
  defp handle_char(state, "X", _projects_dir), do: handle_delete(state)
  defp handle_char(state, "?", _projects_dir), do: State.enter_help_mode(state)
  defp handle_char(state, "1", _projects_dir), do: State.set_active_panel(state, :projects)
  defp handle_char(state, "2", _projects_dir), do: State.set_active_panel(state, :tickets)
  defp handle_char(state, "3", _projects_dir), do: State.set_active_panel(state, :research)
  defp handle_char(state, "4", _projects_dir), do: State.set_active_panel(state, :detail)
  defp handle_char(state, _, _projects_dir), do: state

  defp dispatch_help_mode(state, :escape), do: State.exit_help_mode(state)
  defp dispatch_help_mode(state, :enter), do: State.exit_help_mode(state)
  defp dispatch_help_mode(state, {:char, "q"}), do: State.exit_help_mode(state)
  defp dispatch_help_mode(state, {:char, "?"}), do: State.exit_help_mode(state)
  defp dispatch_help_mode(state, _), do: state

  defp dispatch_modal_mode(%State{modal_data: %{phase: :input}} = state, :escape, _projects_dir) do
    State.exit_modal(state)
    |> State.set_message("Cancelled")
  end

  defp dispatch_modal_mode(%State{modal_data: %{phase: :input}} = state, :enter, projects_dir) do
    handle_modal_submit(state, projects_dir)
  end

  defp dispatch_modal_mode(%State{modal_data: %{phase: :input}} = state, :tab, _projects_dir) do
    State.modal_next_field(state)
  end

  defp dispatch_modal_mode(
         %State{modal_data: %{phase: :input}} = state,
         :shift_tab,
         _projects_dir
       ) do
    State.modal_prev_field(state)
  end

  defp dispatch_modal_mode(
         %State{modal_data: %{phase: :input}} = state,
         :backspace,
         _projects_dir
       ) do
    State.modal_delete_char(state)
  end

  defp dispatch_modal_mode(%State{modal_data: %{phase: :input}} = state, :left, _projects_dir) do
    State.modal_move_cursor_left(state)
  end

  defp dispatch_modal_mode(%State{modal_data: %{phase: :input}} = state, :right, _projects_dir) do
    State.modal_move_cursor_right(state)
  end

  defp dispatch_modal_mode(
         %State{modal_data: %{phase: :input}} = state,
         {:char, char},
         _projects_dir
       ) do
    State.modal_insert_char(state, char)
  end

  defp dispatch_modal_mode(%State{modal_data: %{phase: phase}} = state, :escape, projects_dir)
       when phase in [:completed, :failed] do
    close_modal_and_refresh(state, projects_dir)
  end

  defp dispatch_modal_mode(%State{modal_data: %{phase: phase}} = state, :enter, projects_dir)
       when phase in [:completed, :failed] do
    close_modal_and_refresh(state, projects_dir)
  end

  defp dispatch_modal_mode(
         %State{modal_data: %{phase: phase}} = state,
         {:char, "j"},
         _projects_dir
       )
       when phase != :input do
    State.scroll_modal_down(state)
  end

  defp dispatch_modal_mode(
         %State{modal_data: %{phase: phase}} = state,
         {:char, "k"},
         _projects_dir
       )
       when phase != :input do
    State.scroll_modal_up(state)
  end

  defp dispatch_modal_mode(%State{modal_data: %{phase: phase}} = state, :down, _projects_dir)
       when phase != :input do
    State.scroll_modal_down(state)
  end

  defp dispatch_modal_mode(%State{modal_data: %{phase: phase}} = state, :up, _projects_dir)
       when phase != :input do
    State.scroll_modal_up(state)
  end

  defp dispatch_modal_mode(state, _, _projects_dir), do: state

  defp handle_modal_submit(
         %State{modal_data: %{name_buffer: name, task_buffer: task}} = state,
         _projects_dir
       )
       when name == "" or task == "" do
    State.add_modal_log(state, "Error: Both fields are required")
  end

  defp handle_modal_submit(%State{modal: :plan} = state, projects_dir) do
    run_plan(state, projects_dir)
  end

  defp handle_modal_submit(
         %State{modal: :analyze, modal_data: %{name_buffer: path}} = state,
         projects_dir
       ) do
    expanded_path = Path.expand(path)

    if File.dir?(expanded_path) do
      run_analyze(state, expanded_path, projects_dir)
    else
      State.add_modal_log(state, "Error: Directory not found: #{path}")
    end
  end

  defp close_modal_and_refresh(state, projects_dir) do
    result = state.modal_data.result

    state
    |> State.exit_modal()
    |> State.load_projects(projects_dir)
    |> select_created_project(result)
    |> maybe_load_created_project(result, projects_dir)
  end

  defp select_created_project(state, %{project_id: project_id}) do
    index =
      Enum.find_index(state.projects, fn p -> p.id == project_id end) || 0

    %{state | current_project: index}
  end

  defp select_created_project(state, _), do: %{state | current_project: 0}

  defp maybe_load_created_project(state, %{project_id: project_id}, projects_dir) do
    project_path = Path.join(projects_dir, project_id)
    load_created_project(state, project_path)
  end

  defp maybe_load_created_project(state, _, _projects_dir), do: state

  defp handle_enter(%State{active_panel: :projects} = state, projects_dir) do
    case State.current_project(state) do
      nil ->
        State.set_message(state, "No project selected")

      project ->
        project_path = Path.join(projects_dir, project.id)

        case State.load_tickets(state, project_path) do
          {:ok, new_state} ->
            new_state
            |> State.set_active_panel(:tickets)
            |> auto_view_first_ticket()
            |> State.set_message("Loaded #{length(new_state.data.tickets)} tickets")

          {:error, :not_found} ->
            state
            |> State.load_project_without_tickets(project_path)
            |> State.set_active_panel(:tickets)
            |> State.set_message("No tickets yet. Press 'n' to add a ticket.")

          {:error, reason} ->
            State.set_message(state, "Error: #{inspect(reason)}")
        end
    end
  end

  defp handle_enter(%State{active_panel: :tickets} = state, _projects_dir) do
    case State.current_ticket(state) do
      nil ->
        State.set_message(state, "No ticket selected")

      _ticket ->
        state
        |> State.view_current_ticket()
        |> Map.put(:active_panel, :detail)
    end
  end

  defp handle_enter(%State{active_panel: :research} = state, _projects_dir) do
    case State.current_research_file(state) do
      nil ->
        State.set_message(state, "No file selected")

      _file ->
        state
        |> State.view_current_file()
        |> Map.put(:active_panel, :detail)
    end
  end

  defp handle_enter(state, _projects_dir), do: state

  defp auto_view_first_ticket(%{data: %{tickets: [_ | _]}, selected_ticket: idx} = state)
       when is_integer(idx) do
    State.view_current_ticket(state)
  end

  defp auto_view_first_ticket(state), do: state

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
    attrs = %{title: "", type: :feature, priority: :medium}

    case Tickets.add(data, attrs) do
      {:ok, updated_data, _ticket} ->
        case Tickets.save(project_dir, updated_data) do
          :ok ->
            new_idx = length(updated_data.tickets) - 1

            %{state | data: updated_data, selected_ticket: new_idx, viewed_ticket: new_idx}
            |> State.set_active_panel(:detail)
            |> State.enter_edit_mode()

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

  defp execute_delete_ticket(%State{data: nil} = state) do
    State.set_message(state, "No project loaded")
  end

  defp execute_delete_ticket(%State{data: data, project_dir: project_dir} = state) do
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

  defp execute_confirmed_action(%State{confirm_action: :delete_ticket} = state, _projects_dir) do
    state
    |> State.exit_confirm_mode()
    |> execute_delete_ticket()
  end

  defp execute_confirmed_action(state, _projects_dir) do
    State.exit_confirm_mode(state)
  end

  defp handle_new(%State{active_panel: :projects} = state) do
    State.enter_input_mode(state, :new_project, "New project task: ")
  end

  defp handle_new(%State{active_panel: panel} = state) when panel in [:tickets, :detail] do
    handle_add_ticket(state)
  end

  defp handle_new(state) do
    State.set_message(state, "Switch to projects or tickets panel to create")
  end

  defp handle_plan(%State{active_panel: :projects} = state) do
    State.enter_modal(state, :plan)
  end

  defp handle_plan(state) do
    State.set_message(state, "Switch to projects panel to plan a new project")
  end

  defp handle_analyze(%State{active_panel: :projects} = state) do
    State.enter_modal(state, :analyze)
  end

  defp handle_analyze(state) do
    State.set_message(state, "Switch to projects panel to analyze a codebase")
  end

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

  defp handle_edit(%State{active_panel: panel} = state) when panel in [:tickets, :detail] do
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

  defp handle_delete(%State{active_panel: panel} = state) when panel in [:tickets, :detail] do
    case State.current_ticket(state) do
      nil ->
        State.set_message(state, "No ticket selected")

      ticket ->
        title = String.slice(ticket.title || "(untitled)", 0, 30)

        State.enter_confirm_mode(
          state,
          :delete_ticket,
          "Delete ticket ##{ticket.id} '#{title}'? (y/n)"
        )
    end
  end

  defp handle_delete(state), do: state

  defp create_new_project(state, task, projects_dir) do
    existing_ids = Enum.map(state.projects, & &1.id)
    unique_id = Id.generate_unique_project_id(task, existing_ids)
    project_state = Project.State.new(".", task, project: unique_id)

    case Project.State.save(project_state) do
      :ok ->
        project_path = project_state.project_dir

        state
        |> State.exit_input_mode()
        |> State.load_projects(projects_dir)
        |> Map.put(:current_project, 0)
        |> State.load_project_without_tickets(project_path)
        |> State.set_active_panel(:tickets)
        |> State.set_message("Created project: #{project_state.id}. Press 'n' to add tickets.")

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

  defp run_plan(state, _projects_dir) do
    name = state.modal_data.name_buffer
    task = state.modal_data.task_buffer
    parent = self()

    LogHandler.install(parent)

    modal_state =
      state
      |> State.start_modal_operation()
      |> State.add_modal_log("Project: #{name}")
      |> State.add_modal_log("Task: #{task}")
      |> State.add_modal_log("")

    spawn_link(fn ->
      result =
        Project.start_greenfield(name, task,
          stream: false,
          silent: true,
          progress_pid: parent
        )

      send(parent, {:operation_complete, {:plan, result}})
    end)

    modal_state
  end

  defp run_analyze(state, codebase_path, _projects_dir) do
    task = state.modal_data.task_buffer
    title = state.modal_data.title_buffer
    parent = self()

    LogHandler.install(parent)

    modal_state =
      state
      |> State.start_modal_operation()
      |> State.add_modal_log("Codebase: #{codebase_path}")
      |> maybe_add_title_log(title)
      |> State.add_modal_log("Task: #{task}")
      |> State.add_modal_log("")

    opts = [
      stream: false,
      silent: true,
      progress_pid: parent
    ]

    opts = if title != "", do: Keyword.put(opts, :project, title), else: opts

    spawn_link(fn ->
      result = Project.start(codebase_path, task, opts)
      send(parent, {:operation_complete, {:analyze, result}})
    end)

    modal_state
  end

  defp maybe_add_title_log(state, ""), do: state
  defp maybe_add_title_log(state, title), do: State.add_modal_log(state, "Project: #{title}")

  defp handle_operation_complete(state, {:plan, result}, projects_dir) do
    LogHandler.uninstall()

    case result do
      {:ok, project_id, _result} ->
        state
        |> State.add_modal_log("")
        |> State.add_modal_log("Project created: #{project_id}")
        |> State.add_modal_log("Press Enter or Esc to continue")
        |> State.complete_modal(:completed, %{project_id: project_id})
        |> State.load_projects(projects_dir)

      {:error, reason} ->
        state
        |> State.add_modal_log("")
        |> State.add_modal_log("Plan failed: #{inspect(reason)}")
        |> State.add_modal_log("Press Enter or Esc to continue")
        |> State.complete_modal(:failed, nil)
    end
  end

  defp handle_operation_complete(state, {:analyze, result}, projects_dir) do
    LogHandler.uninstall()

    case result do
      {:ok, project_id, _result} ->
        state
        |> State.add_modal_log("")
        |> State.add_modal_log("Analysis complete: #{project_id}")
        |> State.add_modal_log("Press Enter or Esc to continue")
        |> State.complete_modal(:completed, %{project_id: project_id})
        |> State.load_projects(projects_dir)

      {:error, reason} ->
        state
        |> State.add_modal_log("")
        |> State.add_modal_log("Analyze failed: #{inspect(reason)}")
        |> State.add_modal_log("Press Enter or Esc to continue")
        |> State.complete_modal(:failed, nil)
    end
  end

  defp handle_operation_progress(state, message) do
    State.add_modal_log(state, message)
  end

  defp handle_agent_progress(state, current, total, agent_name) do
    state
    |> State.update_agent_progress(current, total, agent_name)
    |> State.add_modal_log("#{agent_name}...")
  end

  defp handle_log_message(state, message) do
    if state.modal != nil and state.modal_data.phase == :running do
      State.add_modal_log(state, message)
    else
      state
    end
  end

  defp load_created_project(state, output_dir) do
    case State.load_tickets(state, output_dir) do
      {:ok, new_state} ->
        new_state
        |> State.set_active_panel(:tickets)
        |> auto_view_first_ticket()

      {:error, _} ->
        state
    end
  end
end
