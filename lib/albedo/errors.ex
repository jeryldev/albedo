defmodule Albedo.Errors do
  @moduledoc """
  Custom exceptions for Albedo.
  """

  defmodule CodebaseNotFoundError do
    defexception [:path]

    @impl true
    def message(%{path: path}) do
      "Codebase not found at: #{path}"
    end
  end

  defmodule LLMError do
    defexception [:provider, :reason]

    @impl true
    def message(%{provider: provider, reason: reason}) do
      "LLM error (#{provider}): #{inspect(reason)}"
    end
  end

  defmodule ProjectError do
    defexception [:project_id, :reason]

    @impl true
    def message(%{project_id: id, reason: reason}) do
      "Project #{id} error: #{inspect(reason)}"
    end
  end

  defmodule ConfigError do
    defexception [:reason]

    @impl true
    def message(%{reason: reason}) do
      "Configuration error: #{inspect(reason)}"
    end
  end

  defmodule AgentError do
    defexception [:agent, :phase, :reason]

    @impl true
    def message(%{agent: agent, phase: phase, reason: reason}) do
      "Agent #{agent} failed in phase #{phase}: #{inspect(reason)}"
    end
  end

  defmodule SearchError do
    defexception [:reason]

    @impl true
    def message(%{reason: reason}) do
      "Search error: #{inspect(reason)}"
    end
  end
end
