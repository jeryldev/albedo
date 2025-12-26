defmodule Albedo.Project.Worker do
  @moduledoc """
  GenServer that orchestrates a single analysis project.
  Coordinates agents through all phases and manages project state.
  """

  use GenServer

  alias Albedo.Agents
  alias Albedo.Project.{Registry, State}
  alias Albedo.Tickets

  require Logger

  @agent_modules %{
    domain_research: Albedo.Agents.DomainResearcher,
    tech_stack: Albedo.Agents.TechStack,
    architecture: Albedo.Agents.Architecture,
    conventions: Albedo.Agents.Conventions,
    feature_location: Albedo.Agents.FeatureLocator,
    impact_analysis: Albedo.Agents.ImpactTracer,
    change_planning: Albedo.Agents.ChangePlanner
  }

  @phase_dependencies %{
    domain_research: [],
    tech_stack: [:domain_research],
    architecture: [:domain_research, :tech_stack],
    conventions: [:domain_research, :tech_stack, :architecture],
    feature_location: [:domain_research, :tech_stack, :architecture, :conventions],
    impact_analysis: [
      :domain_research,
      :tech_stack,
      :architecture,
      :conventions,
      :feature_location
    ],
    change_planning: :all
  }

  def start_link({codebase_path, task, opts}) do
    GenServer.start_link(__MODULE__, {:new, codebase_path, task, opts})
  end

  def start_link({:greenfield, project_name, task, opts}) do
    GenServer.start_link(__MODULE__, {:greenfield, project_name, task, opts})
  end

  def start_link({:resume, project_dir}) do
    GenServer.start_link(__MODULE__, {:resume, project_dir})
  end

  @impl true
  def init({:new, codebase_path, task, opts}) do
    state = State.new(codebase_path, task, opts)
    Registry.register(state.id)
    State.save(state)
    send(self(), :start_analysis)
    {:ok, state}
  end

  def init({:greenfield, project_name, task, opts}) do
    state = State.new_greenfield(project_name, task, opts)
    Registry.register(state.id)
    State.save(state)
    send(self(), :start_greenfield_planning)
    {:ok, state}
  end

  def init({:resume, project_dir}) do
    case State.load(project_dir) do
      {:ok, state} ->
        Registry.register(state.id)
        send(self(), :resume_analysis)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_result, _from, state) do
    result = build_result(state)
    {:reply, result, state}
  end

  def handle_call({:answer_question, answer}, _from, state) do
    previous_state = get_previous_state(state)
    state = State.answer_question(state, answer, previous_state)
    State.save(state)
    send(self(), :continue_analysis)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:start_analysis, state) do
    print_phase_header(state, "Starting analysis")
    state = start_next_phase(state)
    {:noreply, state}
  end

  def handle_info(:start_greenfield_planning, state) do
    project_name = state.context[:project_name] || "new project"
    print_phase_header(state, "Planning greenfield project: #{project_name}")
    state = start_next_phase(state)
    {:noreply, state}
  end

  def handle_info(:resume_analysis, state) do
    print_phase_header(state, "Resuming analysis")
    state = start_next_phase(state)
    {:noreply, state}
  end

  def handle_info(:continue_analysis, state) do
    state = start_next_phase(state)
    {:noreply, state}
  end

  def handle_info({:agent_complete, phase, findings}, state) do
    print_phase_complete(state, phase)
    state = State.complete_phase(state, phase, findings)
    State.save(state)

    if State.complete?(state) do
      state = finalize_project(state)
      {:stop, :normal, state}
    else
      state = start_next_phase(state)
      {:noreply, state}
    end
  end

  def handle_info({:agent_failed, phase, reason}, state) do
    Logger.error("Agent failed for phase #{phase}: #{inspect(reason)}")
    state = State.fail_phase(state, phase, reason)
    State.save(state)
    print_phase_failed(state, phase, reason)
    {:stop, :normal, state}
  end

  defp start_next_phase(state) do
    case State.first_incomplete_phase(state) do
      nil ->
        state = State.transition(state, :completed)
        State.save(state)
        state

      phase ->
        start_phase(state, phase)
    end
  end

  defp start_phase(state, phase) do
    print_phase_start(state, phase)
    state = State.start_phase(state, phase)
    State.save(state)

    context = build_agent_context(state, phase)
    agent_module = @agent_modules[phase]

    {:ok, _pid} =
      Agents.Supervisor.start_agent(agent_module, %{
        project_id: state.id,
        project_dir: state.project_dir,
        codebase_path: state.codebase_path,
        task: state.task,
        phase: phase,
        context: context,
        output_file: State.phase_output_file(phase)
      })

    state
  end

  defp build_agent_context(state, phase) do
    base_context = build_phase_context(state, phase)
    greenfield_context = build_greenfield_context(state)
    Map.merge(greenfield_context, base_context)
  end

  defp build_phase_context(state, :change_planning), do: state.context

  defp build_phase_context(state, phase) do
    deps = @phase_dependencies[phase]

    Enum.reduce(deps, %{task: state.task}, fn dep, acc ->
      Map.put(acc, dep, state.context[dep])
    end)
  end

  defp build_greenfield_context(%{context: %{greenfield: true} = context}) do
    %{
      greenfield: true,
      project_name: context[:project_name],
      stack: context[:stack],
      database: context[:database]
    }
  end

  defp build_greenfield_context(_state), do: %{}

  defp finalize_project(state) do
    header =
      if state.context[:greenfield],
        do: "Planning complete",
        else: "Analysis complete"

    print_phase_header(state, header)

    summary =
      build_summary(state)
      |> maybe_add_greenfield_summary(state)

    save_tickets(state)

    state = State.set_summary(state, summary)
    State.save(state)
    state
  end

  defp save_tickets(state) do
    tickets = get_in(state.context, [:change_planning, :tickets]) || []

    if tickets != [] do
      project_name =
        if state.context[:greenfield] do
          state.context[:project_name]
        else
          nil
        end

      tickets_data = Tickets.new(state.id, state.task, tickets, project_name: project_name)
      Tickets.save(state.project_dir, tickets_data)

      unless silent?(state) do
        Owl.IO.puts(Owl.Data.tag("  │  └─ ✓ Saved tickets.json", :green))
      end
    end
  end

  defp build_summary(state) do
    %{
      tickets_count: get_in(state.context, [:change_planning, :tickets_count]) || 0,
      total_points: get_in(state.context, [:change_planning, :total_points]) || 0,
      files_to_create: get_in(state.context, [:change_planning, :files_to_create]) || 0,
      files_to_modify: get_in(state.context, [:change_planning, :files_to_modify]) || 0,
      risks_identified: get_in(state.context, [:change_planning, :risks_identified]) || 0
    }
  end

  defp maybe_add_greenfield_summary(summary, state) do
    if state.context[:greenfield] do
      Map.merge(summary, %{
        recommended_stack: get_in(state.context, [:change_planning, :recommended_stack]),
        setup_steps: get_in(state.context, [:change_planning, :setup_steps]) || 0
      })
    else
      summary
    end
  end

  defp build_result(state) do
    base_result = %{
      project_id: state.id,
      output_path: Path.join(state.project_dir, "FEATURE.md"),
      tickets_count: state.summary[:tickets_count],
      total_points: state.summary[:total_points],
      files_to_create: state.summary[:files_to_create],
      files_to_modify: state.summary[:files_to_modify],
      risks_identified: state.summary[:risks_identified]
    }

    if state.context[:greenfield] do
      Map.merge(base_result, %{
        recommended_stack: state.summary[:recommended_stack],
        setup_steps: state.summary[:setup_steps]
      })
    else
      base_result
    end
  end

  defp get_previous_state(state) do
    current_phase = State.first_incomplete_phase(state)

    if current_phase do
      State.phase_state_name(current_phase)
    else
      :completed
    end
  end

  defp print_phase_header(state, message) do
    send_progress(state, message)

    unless silent?(state) do
      Owl.IO.puts(Owl.Data.tag("\n#{message}", :cyan))
      IO.puts(String.duplicate("─", 50))
    end
  end

  defp print_phase_start(state, phase) do
    phase_name = phase |> to_string() |> String.replace("_", " ") |> String.capitalize()
    {current, total} = calculate_agent_progress(state, phase)
    send_agent_progress(state, current, total, phase_name)

    unless silent?(state) do
      Owl.IO.puts(Owl.Data.tag("  ├─ #{phase_name}...", :light_black))
    end
  end

  defp calculate_agent_progress(state, current_phase) do
    phases_to_run =
      State.phases()
      |> Enum.reject(fn phase -> state.phases[phase].status == :skipped end)

    total = length(phases_to_run)
    current = Enum.find_index(phases_to_run, &(&1 == current_phase)) + 1
    {current, total}
  end

  defp print_phase_complete(state, phase) do
    output_file = State.phase_output_file(phase)
    send_progress(state, "✓ Saved #{output_file}")

    unless silent?(state) do
      Owl.IO.puts(Owl.Data.tag("  │  └─ ✓ Saved #{output_file}", :green))
    end
  end

  defp print_phase_failed(state, phase, reason) do
    phase_name = phase |> to_string() |> String.replace("_", " ") |> String.capitalize()
    send_progress(state, "✗ #{phase_name} failed: #{inspect(reason)}")

    unless silent?(state) do
      Owl.IO.puts(Owl.Data.tag("  │  └─ ✗ #{phase_name} failed: #{inspect(reason)}", :red))

      Owl.IO.puts(
        Owl.Data.tag(
          "\nProject failed. You can retry with: albedo resume <project_path>",
          :yellow
        )
      )
    end
  end

  defp send_progress(state, message) do
    case state.config[:progress_pid] do
      pid when is_pid(pid) -> send(pid, {:operation_progress, message})
      _ -> :ok
    end
  end

  defp send_agent_progress(state, current, total, agent_name) do
    case state.config[:progress_pid] do
      pid when is_pid(pid) ->
        send(pid, {:agent_progress, current, total, agent_name})

      _ ->
        :ok
    end
  end

  defp silent?(state), do: state.config[:silent] == true
end
