defmodule Albedo.Session.SupervisorTest do
  use ExUnit.Case, async: false

  alias Albedo.Session.Supervisor, as: SessionSupervisor

  describe "supervisor behavior" do
    test "supervisor is running" do
      assert Process.whereis(SessionSupervisor) != nil
    end

    test "list_sessions returns list format" do
      sessions = SessionSupervisor.list_sessions()
      assert is_list(sessions)
    end
  end

  describe "session lifecycle" do
    test "stop_session terminates child" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      result = SessionSupervisor.stop_session(pid)
      assert result == {:error, :not_found}
    end
  end

  describe "child spec building" do
    test "builds worker spec for existing codebase" do
      spec = build_child_spec("/path/to/code", "add feature", [])

      assert spec == {Albedo.Session.Worker, {"/path/to/code", "add feature", []}}
    end

    test "builds worker spec for greenfield" do
      spec = build_greenfield_child_spec("my_app", "create app", [])

      assert spec == {Albedo.Session.Worker, {:greenfield, "my_app", "create app", []}}
    end

    test "builds worker spec for resume" do
      spec = build_resume_child_spec("/path/to/session")

      assert spec == {Albedo.Session.Worker, {:resume, "/path/to/session"}}
    end
  end

  defp build_child_spec(codebase_path, task, opts) do
    {Albedo.Session.Worker, {codebase_path, task, opts}}
  end

  defp build_greenfield_child_spec(project_name, task, opts) do
    {Albedo.Session.Worker, {:greenfield, project_name, task, opts}}
  end

  defp build_resume_child_spec(session_dir) do
    {Albedo.Session.Worker, {:resume, session_dir}}
  end
end
