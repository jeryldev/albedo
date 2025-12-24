defmodule Albedo.Agents.Base do
  @moduledoc """
  Common behavior and macros for all agents.
  Each agent implements the investigate/1 and format_output/1 callbacks.
  """

  @callback investigate(context :: map()) :: {:ok, findings :: map()} | {:error, term()}
  @callback format_output(findings :: map()) :: String.t()

  defmacro __using__(_opts) do
    quote do
      use GenServer
      @behaviour Albedo.Agents.Base

      require Logger

      alias Albedo.LLM.Client, as: LLM
      alias Albedo.Session.Registry

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts)
      end

      @impl GenServer
      def init(opts) do
        state = %{
          session_id: opts[:session_id],
          session_dir: opts[:session_dir],
          codebase_path: opts[:codebase_path],
          task: opts[:task],
          phase: opts[:phase],
          context: opts[:context] || %{},
          output_file: opts[:output_file]
        }

        send(self(), :investigate)
        {:ok, state}
      end

      @impl GenServer
      def handle_info(:investigate, state) do
        Logger.info("Agent #{__MODULE__} starting investigation for phase #{state.phase}")

        case investigate(state) do
          {:ok, findings} ->
            output = format_output(findings)
            save_output(state.session_dir, state.output_file, output)
            notify_session(state.session_id, state.phase, findings)
            {:stop, :normal, state}

          {:error, reason} ->
            Logger.error("Agent #{__MODULE__} failed: #{inspect(reason)}")
            notify_session_failed(state.session_id, state.phase, reason)
            {:stop, :normal, state}
        end
      end

      defp save_output(session_dir, output_file, content) do
        File.mkdir_p!(session_dir)
        path = Path.join(session_dir, output_file)
        File.write!(path, content)
        Logger.info("Saved output to #{path}")
      end

      defp notify_session(session_id, phase, findings) do
        Registry.notify_agent_complete(session_id, phase, findings)
      end

      defp notify_session_failed(session_id, phase, reason) do
        Registry.notify_agent_failed(session_id, phase, reason)
      end

      defp call_llm(prompt, opts \\ []) do
        LLM.chat(prompt, opts)
      end
    end
  end

  @doc """
  Helper to build markdown sections.
  """
  def markdown_section(title, content) do
    """
    ## #{title}

    #{content}
    """
  end

  @doc """
  Helper to build markdown tables.
  """
  def markdown_table(headers, rows) do
    header_row = "| " <> Enum.join(headers, " | ") <> " |"
    separator = "| " <> Enum.map_join(headers, " | ", fn _ -> "---" end) <> " |"

    data_rows =
      Enum.map_join(rows, "\n", fn row ->
        "| " <> Enum.join(row, " | ") <> " |"
      end)

    """
    #{header_row}
    #{separator}
    #{data_rows}
    """
  end

  @doc """
  Helper to build code blocks.
  """
  def code_block(content, language \\ "elixir") do
    """
    ```#{language}
    #{content}
    ```
    """
  end

  @doc """
  Helper to format a mermaid diagram.
  """
  def mermaid_diagram(content) do
    """
    ```mermaid
    #{content}
    ```
    """
  end
end
