defmodule Albedo.Project.State do
  @moduledoc """
  Project state struct and state machine logic.
  """

  alias Albedo.Utils.Id

  @type phase_status :: :pending | :in_progress | :completed | :failed | :skipped

  @type phase_state :: %{
          status: phase_status(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: non_neg_integer() | nil,
          output_file: String.t() | nil,
          error: term() | nil
        }

  @type project_state ::
          :created
          | :researching_domain
          | :analyzing_tech_stack
          | :analyzing_architecture
          | :analyzing_conventions
          | :locating_feature
          | :analyzing_impact
          | :planning_changes
          | :completed
          | :failed
          | :paused

  @type t :: %__MODULE__{
          id: String.t(),
          codebase_path: String.t(),
          task: String.t(),
          state: project_state(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          project_dir: String.t(),
          config: map(),
          phases: %{
            domain_research: phase_state(),
            tech_stack: phase_state(),
            architecture: phase_state(),
            conventions: phase_state(),
            feature_location: phase_state(),
            impact_analysis: phase_state(),
            change_planning: phase_state()
          },
          context: map(),
          clarifying_questions: list(map()),
          summary: map() | nil
        }

  defstruct [
    :id,
    :codebase_path,
    :task,
    :state,
    :created_at,
    :updated_at,
    :project_dir,
    config: %{},
    phases: %{},
    context: %{},
    clarifying_questions: [],
    summary: nil
  ]

  @phases [
    :domain_research,
    :tech_stack,
    :architecture,
    :conventions,
    :feature_location,
    :impact_analysis,
    :change_planning
  ]

  @phase_to_state %{
    domain_research: :researching_domain,
    tech_stack: :analyzing_tech_stack,
    architecture: :analyzing_architecture,
    conventions: :analyzing_conventions,
    feature_location: :locating_feature,
    impact_analysis: :analyzing_impact,
    change_planning: :planning_changes
  }

  @phase_output_files %{
    domain_research: "00_domain_research.md",
    tech_stack: "01_tech_stack.md",
    architecture: "02_architecture.md",
    conventions: "03_conventions.md",
    feature_location: "04_feature_location.md",
    impact_analysis: "05_impact_analysis.md",
    change_planning: "FEATURE.md"
  }

  @doc """
  Create a new project state.
  """
  def new(codebase_path, task, opts \\ []) do
    now = DateTime.utc_now()
    id = Id.generate_project_id(task, opts[:project])
    config = Albedo.Config.load!()
    project_dir = Path.join(Albedo.Config.projects_dir(config), id)

    %__MODULE__{
      id: id,
      codebase_path: codebase_path,
      task: task,
      state: :created,
      created_at: now,
      updated_at: now,
      project_dir: project_dir,
      config: build_project_config(opts),
      phases: init_phases(),
      context: %{},
      clarifying_questions: [],
      summary: nil
    }
  end

  @doc """
  Create a new greenfield project state (no existing codebase).
  Skips code analysis phases and goes directly to planning.
  """
  def new_greenfield(project_name, task, opts \\ []) do
    now = DateTime.utc_now()
    custom_name = opts[:project] || project_name
    id = Id.generate_project_id(task, custom_name)
    config = Albedo.Config.load!()
    project_dir = Path.join(Albedo.Config.projects_dir(config), id)

    %__MODULE__{
      id: id,
      codebase_path: nil,
      task: task,
      state: :created,
      created_at: now,
      updated_at: now,
      project_dir: project_dir,
      config: build_greenfield_config(project_name, opts),
      phases: init_greenfield_phases(),
      context: %{
        greenfield: true,
        project_name: project_name,
        stack: opts[:stack],
        database: opts[:database]
      },
      clarifying_questions: [],
      summary: nil
    }
  end

  @doc """
  Load project state from a project directory.
  """
  def load(project_dir) do
    project_file = Path.join(project_dir, "project.json")

    with {:ok, content} <- File.read(project_file),
         {:ok, data} <- Jason.decode(content) do
      {:ok, from_json(data, project_dir)}
    end
  end

  @doc """
  Save project state to disk.
  """
  def save(%__MODULE__{} = state) do
    File.mkdir_p!(state.project_dir)
    project_file = Path.join(state.project_dir, "project.json")
    content = Jason.encode!(to_json(state), pretty: true)
    File.write(project_file, content)
  end

  @doc """
  Get all phases in order.
  """
  def phases, do: @phases

  @doc """
  Get the output file name for a phase.
  """
  def phase_output_file(phase), do: @phase_output_files[phase]

  @doc """
  Get the project state name for a phase.
  """
  def phase_state_name(phase), do: @phase_to_state[phase]

  @doc """
  Get the next phase after the given phase.
  """
  def next_phase(current_phase) do
    index = Enum.find_index(@phases, &(&1 == current_phase))

    if index && index < length(@phases) - 1 do
      Enum.at(@phases, index + 1)
    else
      nil
    end
  end

  @doc """
  Get the first incomplete phase.
  """
  def first_incomplete_phase(%__MODULE__{phases: phases}) do
    Enum.find(@phases, fn phase ->
      phases[phase].status == :pending
    end)
  end

  @doc """
  Transition to a new state.
  """
  def transition(%__MODULE__{} = state, new_state) do
    %{state | state: new_state, updated_at: DateTime.utc_now()}
  end

  @doc """
  Start a phase.
  """
  def start_phase(%__MODULE__{} = state, phase) do
    now = DateTime.utc_now()

    phases =
      Map.update!(state.phases, phase, fn phase_state ->
        %{phase_state | status: :in_progress, started_at: now}
      end)

    project_state = @phase_to_state[phase]

    %{state | phases: phases, state: project_state, updated_at: now}
  end

  @doc """
  Complete a phase.
  """
  def complete_phase(%__MODULE__{} = state, phase, findings \\ %{}) do
    now = DateTime.utc_now()
    phase_state = state.phases[phase]
    started_at = phase_state.started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    phases =
      Map.update!(state.phases, phase, fn ps ->
        %{
          ps
          | status: :completed,
            completed_at: now,
            duration_ms: duration_ms,
            output_file: @phase_output_files[phase]
        }
      end)

    context = Map.put(state.context, phase, findings)

    next_state =
      case next_phase(phase) do
        nil -> :completed
        next -> @phase_to_state[next]
      end

    %{state | phases: phases, context: context, state: next_state, updated_at: now}
  end

  @doc """
  Fail a phase.
  """
  def fail_phase(%__MODULE__{} = state, phase, error) do
    now = DateTime.utc_now()

    phases =
      Map.update!(state.phases, phase, fn ps ->
        %{ps | status: :failed, error: error}
      end)

    %{state | phases: phases, state: :failed, updated_at: now}
  end

  @doc """
  Pause for clarifying question.
  """
  def pause(%__MODULE__{} = state, question) do
    questions =
      state.clarifying_questions ++ [%{question: question, asked_at: DateTime.utc_now()}]

    %{state | state: :paused, clarifying_questions: questions, updated_at: DateTime.utc_now()}
  end

  @doc """
  Answer a clarifying question and resume.
  """
  def answer_question(%__MODULE__{} = state, answer, resume_state) do
    questions =
      List.update_at(state.clarifying_questions, -1, fn q ->
        Map.put(q, :answer, answer)
      end)

    %{
      state
      | state: resume_state,
        clarifying_questions: questions,
        updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Set the final summary.
  """
  def set_summary(%__MODULE__{} = state, summary) do
    %{state | summary: summary, updated_at: DateTime.utc_now()}
  end

  @doc """
  Check if project is complete.
  """
  def complete?(%__MODULE__{state: :completed}), do: true
  def complete?(%__MODULE__{}), do: false

  @doc """
  Check if project has failed.
  """
  def failed?(%__MODULE__{state: :failed}), do: true
  def failed?(%__MODULE__{}), do: false

  defp init_phases do
    @phases
    |> Enum.map(fn phase ->
      {phase,
       %{
         status: :pending,
         started_at: nil,
         completed_at: nil,
         duration_ms: nil,
         output_file: nil,
         error: nil
       }}
    end)
    |> Map.new()
  end

  defp build_project_config(opts) do
    %{
      interactive: opts[:interactive] || false,
      silent: opts[:silent] || false,
      progress_pid: opts[:progress_pid]
    }
  end

  defp build_greenfield_config(project_name, opts) do
    %{
      greenfield: true,
      project_name: project_name,
      stack: opts[:stack],
      database: opts[:database],
      interactive: opts[:interactive] || false,
      silent: opts[:silent] || false,
      progress_pid: opts[:progress_pid]
    }
  end

  defp init_greenfield_phases do
    skipped_phases = [
      :conventions,
      :feature_location,
      :impact_analysis
    ]

    @phases
    |> Enum.map(fn phase ->
      status = if phase in skipped_phases, do: :skipped, else: :pending

      {phase,
       %{
         status: status,
         started_at: nil,
         completed_at: nil,
         duration_ms: nil,
         output_file: nil,
         error: nil
       }}
    end)
    |> Map.new()
  end

  defp to_json(%__MODULE__{} = state) do
    %{
      "id" => state.id,
      "codebase_path" => state.codebase_path,
      "task" => state.task,
      "state" => to_string(state.state),
      "created_at" => DateTime.to_iso8601(state.created_at),
      "updated_at" => DateTime.to_iso8601(state.updated_at),
      "config" => config_to_json(state.config),
      "phases" => phases_to_json(state.phases),
      "clarifying_questions" => state.clarifying_questions,
      "summary" => state.summary
    }
  end

  defp config_to_json(config) do
    Map.drop(config, [:progress_pid])
  end

  defp phases_to_json(phases) do
    phases
    |> Enum.map(fn {phase, ps} ->
      {to_string(phase),
       %{
         "status" => to_string(ps.status),
         "started_at" => ps.started_at && DateTime.to_iso8601(ps.started_at),
         "completed_at" => ps.completed_at && DateTime.to_iso8601(ps.completed_at),
         "duration_ms" => ps.duration_ms,
         "output_file" => ps.output_file,
         "error" => ps.error && inspect(ps.error)
       }}
    end)
    |> Map.new()
  end

  defp from_json(data, project_dir) do
    %__MODULE__{
      id: data["id"],
      codebase_path: data["codebase_path"],
      task: data["task"],
      state: String.to_existing_atom(data["state"]),
      created_at: parse_datetime(data["created_at"]),
      updated_at: parse_datetime(data["updated_at"]),
      project_dir: project_dir,
      config: data["config"] || %{},
      phases: phases_from_json(data["phases"]),
      context: %{},
      clarifying_questions: data["clarifying_questions"] || [],
      summary: atomize_summary(data["summary"])
    }
  end

  defp atomize_summary(nil), do: nil

  defp atomize_summary(summary) when is_map(summary) do
    summary
    |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
    |> Map.new()
  end

  defp phases_from_json(nil), do: init_phases()

  defp phases_from_json(phases) do
    @phases
    |> Enum.map(fn phase ->
      key = to_string(phase)

      ps =
        if phases[key] do
          %{
            status: String.to_existing_atom(phases[key]["status"]),
            started_at: parse_datetime(phases[key]["started_at"]),
            completed_at: parse_datetime(phases[key]["completed_at"]),
            duration_ms: phases[key]["duration_ms"],
            output_file: phases[key]["output_file"],
            error: phases[key]["error"]
          }
        else
          %{
            status: :pending,
            started_at: nil,
            completed_at: nil,
            duration_ms: nil,
            output_file: nil,
            error: nil
          }
        end

      {phase, ps}
    end)
    |> Map.new()
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
