defmodule Albedo.Errors do
  @moduledoc """
  Custom exceptions for Albedo.
  """

  defmodule LLMError do
    defexception [:provider, :reason]

    @impl true
    def message(%{provider: provider, reason: reason}) do
      "LLM error (#{provider}): #{inspect(reason)}"
    end
  end

  defmodule ConfigError do
    defexception [:reason]

    @impl true
    def message(%{reason: reason}) do
      "Configuration error: #{inspect(reason)}"
    end
  end
end
