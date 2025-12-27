defmodule Albedo.TUI.LogHandler do
  @moduledoc """
  Custom Erlang logger handler that forwards log messages to the TUI process.
  Used during modal operations to display logs inside the modal.
  """

  @behaviour :logger_handler

  @handler_id :tui_log_handler
  @default_handler :default

  @doc """
  Installs the log handler that forwards messages to the given PID.
  Disables the default console handler to prevent duplicate output.
  """
  def install(pid) when is_pid(pid) do
    # First remove any existing handler (in case of re-install)
    :logger.remove_handler(@handler_id)

    # Silence the default console handler
    :logger.set_handler_config(@default_handler, :level, :none)

    handler_config = %{
      config: %{target_pid: pid},
      level: :all
    }

    :logger.add_handler(@handler_id, __MODULE__, handler_config)
  end

  @doc """
  Removes the log handler and restores the default console handler.
  """
  def uninstall do
    :logger.remove_handler(@handler_id)
    :logger.set_handler_config(@default_handler, :level, :info)
  end

  @doc """
  Erlang logger handler callback - called for each log event.
  """
  @impl :logger_handler
  def log(%{level: level, msg: msg}, %{config: %{target_pid: pid}}) do
    message = format_message(level, msg)

    if message != "" do
      send(pid, {:log_message, message})
    end
  end

  def log(_event, _config), do: :ok

  defp format_message(level, {:string, msg}) do
    format_with_level(level, IO.iodata_to_binary(msg))
  end

  defp format_message(level, {:report, report}) do
    format_with_level(level, inspect(report))
  end

  defp format_message(level, {format, args}) do
    formatted = :io_lib.format(format, args) |> IO.iodata_to_binary()
    format_with_level(level, formatted)
  end

  defp format_message(_level, _msg), do: ""

  defp format_with_level(:info, msg), do: msg
  defp format_with_level(:debug, msg), do: "[debug] #{msg}"
  defp format_with_level(:warning, msg), do: "[warn] #{msg}"
  defp format_with_level(:error, msg), do: "[error] #{msg}"
  defp format_with_level(_level, msg), do: msg
end
