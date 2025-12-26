defmodule Albedo.Project do
  @moduledoc """
  Public interface for managing analysis projects.
  """

  alias Albedo.{Config, Project.State}
  alias Albedo.Project.{Registry, Supervisor}

  @timeout 600_000

  @doc """
  Create a new project folder with the given task description.

  Returns `{:ok, project_id, project_dir}` on success, or `{:error, reason}` on failure.
  """
  def create_folder(task, opts \\ []) do
    state = State.new(".", task, opts)

    case State.save(state) do
      :ok -> {:ok, state.id, state.project_dir}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Rename a project folder.

  Takes the current project ID and a new name, renames the folder, and updates
  the project.json file with the new ID.

  Returns `{:ok, new_project_id, new_project_dir}` on success, or `{:error, reason}` on failure.
  """
  def rename_folder(project_id, new_name) do
    config = Config.load!()
    projects_dir = Config.projects_dir(config)
    old_project_dir = Path.join(projects_dir, project_id)

    sanitized_name =
      new_name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    new_project_dir = Path.join(projects_dir, sanitized_name)

    with {:exists, true} <- {:exists, File.dir?(old_project_dir)},
         {:name_different, true} <- {:name_different, old_project_dir != new_project_dir},
         {:no_conflict, false} <- {:no_conflict, File.exists?(new_project_dir)},
         :ok <- File.rename(old_project_dir, new_project_dir),
         :ok <- update_project_id(new_project_dir, sanitized_name) do
      {:ok, sanitized_name, new_project_dir}
    else
      {:exists, false} -> {:error, :project_not_found}
      {:name_different, false} -> {:ok, project_id, old_project_dir}
      {:no_conflict, true} -> {:error, :name_already_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Delete a project folder and all its contents.

  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def delete_folder(project_id) do
    config = Config.load!()
    projects_dir = Config.projects_dir(config)
    project_dir = Path.join(projects_dir, project_id)

    if File.dir?(project_dir) do
      case File.rm_rf(project_dir) do
        {:ok, _} -> :ok
        {:error, reason, _} -> {:error, reason}
      end
    else
      {:error, :project_not_found}
    end
  end

  @doc """
  List all project folders.

  Returns a list of maps containing project information.
  """
  def list_folders do
    config = Config.load!()
    projects_dir = Config.projects_dir(config)

    case File.ls(projects_dir) do
      {:ok, dirs} ->
        dirs
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.filter(&has_project_file?(projects_dir, &1))
        |> Enum.sort(:desc)
        |> Enum.map(&load_project_info(projects_dir, &1))

      {:error, :enoent} ->
        []

      {:error, _reason} ->
        []
    end
  end

  defp has_project_file?(projects_dir, dir) do
    project_file = Path.join([projects_dir, dir, "project.json"])
    File.exists?(project_file)
  end

  defp load_project_info(projects_dir, id) do
    project_file = Path.join([projects_dir, id, "project.json"])

    with {:ok, content} <- File.read(project_file),
         {:ok, data} <- Jason.decode(content) do
      %{
        id: id,
        state: data["state"] || "unknown",
        task: data["task"] || "",
        created_at: data["created_at"],
        project_dir: Path.join(projects_dir, id)
      }
    else
      _ ->
        %{
          id: id,
          state: "unknown",
          task: "",
          created_at: nil,
          project_dir: Path.join(projects_dir, id)
        }
    end
  end

  defp update_project_id(project_dir, new_id) do
    project_file = Path.join(project_dir, "project.json")

    with {:ok, content} <- File.read(project_file),
         {:ok, data} <- Jason.decode(content) do
      updated_data = Map.put(data, "id", new_id)
      File.write(project_file, Jason.encode!(updated_data, pretty: true))
    end
  end

  @doc """
  Start a new analysis project and wait for completion.
  """
  def start(codebase_path, task, opts \\ []) do
    case Supervisor.start_project(codebase_path, task, opts) do
      {:ok, pid} ->
        wait_for_completion(pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Start a new greenfield planning project (no existing codebase).
  """
  def start_greenfield(project_name, task, opts \\ []) do
    greenfield_opts = Keyword.put(opts, :greenfield, true)

    case Supervisor.start_greenfield_project(project_name, task, greenfield_opts) do
      {:ok, pid} ->
        wait_for_completion(pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resume an existing project and wait for completion.
  """
  def resume(project_dir) do
    case Supervisor.resume_project(project_dir) do
      {:ok, pid} ->
        wait_for_completion(pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Re-run the planning phase with different parameters.
  """
  def replan(project_dir, opts \\ []) do
    case State.load(project_dir) do
      {:ok, state} ->
        state = reset_planning_phase(state, opts)
        State.save(state)
        resume(project_dir)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Answer a clarifying question in a paused project.
  """
  def answer_question(project_id, answer) do
    Registry.call(project_id, {:answer_question, answer})
  end

  @doc """
  Get the current state of a project.
  """
  def get_state(project_id) do
    Registry.call(project_id, :get_state)
  end

  defp wait_for_completion(pid) do
    ref = Process.monitor(pid)

    state = GenServer.call(pid, :get_state, @timeout)
    project_dir = state.project_dir

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        case State.load(project_dir) do
          {:ok, final_state} ->
            if State.failed?(final_state) do
              {:error, {:phase_failed, final_state.id, project_dir}}
            else
              result = build_result(final_state)
              {:ok, final_state.id, result}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, reason}
    after
      @timeout ->
        Process.demonitor(ref, [:flush])
        {:error, :timeout}
    end
  catch
    :exit, {:noproc, _} ->
      {:error, :project_not_found}

    :exit, {:timeout, _} ->
      {:error, :timeout}
  end

  defp build_result(state) do
    %{
      project_id: state.id,
      output_path: Path.join(state.project_dir, "FEATURE.md"),
      tickets_count: state.summary[:tickets_count],
      total_points: state.summary[:total_points],
      files_to_create: state.summary[:files_to_create],
      files_to_modify: state.summary[:files_to_modify],
      risks_identified: state.summary[:risks_identified],
      recommended_stack: state.summary[:recommended_stack],
      setup_steps: state.summary[:setup_steps]
    }
  end

  defp reset_planning_phase(state, opts) do
    scope = opts[:scope] || "full"

    phases_to_reset =
      case scope do
        "minimal" -> [:change_planning]
        _ -> [:impact_analysis, :change_planning]
      end

    phases =
      Enum.reduce(phases_to_reset, state.phases, fn phase, acc ->
        Map.update!(acc, phase, fn ps ->
          %{ps | status: :pending, started_at: nil, completed_at: nil, duration_ms: nil}
        end)
      end)

    %{state | phases: phases, state: :created}
  end
end
