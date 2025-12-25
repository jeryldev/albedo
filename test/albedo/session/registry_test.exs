defmodule Albedo.Session.RegistryTest do
  use ExUnit.Case, async: false

  alias Albedo.Session.Registry

  describe "registry behavior" do
    test "registry is running" do
      assert Process.whereis(Registry) != nil
    end
  end

  describe "registration and lookup" do
    test "lookup returns not_found for unregistered session" do
      assert Registry.lookup("nonexistent-session") == {:error, :not_found}
    end

    test "get_session_id returns not_found for unregistered pid" do
      pid = spawn(fn -> Process.sleep(100) end)
      assert Registry.get_session_id(pid) == {:error, :not_found}
    end
  end

  describe "message sending" do
    test "send_message returns error for unregistered session" do
      result = Registry.send_message("nonexistent", :test_message)
      assert result == {:error, :not_found}
    end

    test "call returns error for unregistered session" do
      result = Registry.call("nonexistent", :test_call, 100)
      assert result == {:error, :not_found}
    end
  end

  describe "notification helpers" do
    test "notify_agent_complete returns error for unregistered session" do
      result = Registry.notify_agent_complete("nonexistent", :domain, %{})
      assert result == {:error, :not_found}
    end

    test "notify_agent_failed returns error for unregistered session" do
      result = Registry.notify_agent_failed("nonexistent", :domain, :timeout)
      assert result == {:error, :not_found}
    end
  end

  describe "child_spec" do
    test "returns valid child spec" do
      spec = Registry.child_spec([])

      assert spec.id == Registry
      assert spec.start == {Registry, :start_link, [[]]}
      assert spec.type == :worker
    end
  end

  describe "lookup helper" do
    test "extracts pid from registry result" do
      registry_result = [{self(), nil}]
      result = extract_pid_from_lookup(registry_result)
      assert result == {:ok, self()}
    end

    test "returns not_found for empty result" do
      result = extract_pid_from_lookup([])
      assert result == {:error, :not_found}
    end
  end

  describe "session_id extraction" do
    test "extracts first key from keys list" do
      keys = ["session-123", "session-456"]
      result = extract_session_id(keys)
      assert result == {:ok, "session-123"}
    end

    test "returns not_found for empty keys" do
      result = extract_session_id([])
      assert result == {:error, :not_found}
    end
  end

  defp extract_pid_from_lookup(registry_result) do
    case registry_result do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp extract_session_id(keys) do
    case keys do
      [session_id | _] -> {:ok, session_id}
      [] -> {:error, :not_found}
    end
  end
end
