defmodule Albedo.Project.SupervisorTest do
  use ExUnit.Case, async: false

  alias Albedo.Project.Supervisor, as: ProjectSupervisor

  describe "supervisor behavior" do
    test "supervisor is running" do
      assert Process.whereis(ProjectSupervisor) != nil
    end

    test "list_projects returns list format" do
      projects = ProjectSupervisor.list_projects()
      assert is_list(projects)
    end
  end

  describe "project lifecycle" do
    test "stop_project terminates child" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      result = ProjectSupervisor.stop_project(pid)
      assert result == {:error, :not_found}
    end
  end

  describe "child spec building" do
    test "builds worker spec for existing codebase" do
      spec = build_child_spec("/path/to/code", "add feature", [])

      assert spec == {Albedo.Project.Worker, {"/path/to/code", "add feature", []}}
    end

    test "builds worker spec for greenfield" do
      spec = build_greenfield_child_spec("my_app", "create app", [])

      assert spec == {Albedo.Project.Worker, {:greenfield, "my_app", "create app", []}}
    end

    test "builds worker spec for resume" do
      spec = build_resume_child_spec("/path/to/project")

      assert spec == {Albedo.Project.Worker, {:resume, "/path/to/project"}}
    end
  end

  defp build_child_spec(codebase_path, task, opts) do
    {Albedo.Project.Worker, {codebase_path, task, opts}}
  end

  defp build_greenfield_child_spec(project_name, task, opts) do
    {Albedo.Project.Worker, {:greenfield, project_name, task, opts}}
  end

  defp build_resume_child_spec(project_dir) do
    {Albedo.Project.Worker, {:resume, project_dir}}
  end
end
