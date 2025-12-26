defmodule Albedo.Test.SessionHelpers do
  @moduledoc """
  Test helpers for session management.
  """

  @doc """
  Create a temporary session directory.
  """
  def tmp_session_dir do
    id = :rand.uniform(999_999)
    dir = Path.join(System.tmp_dir!(), "albedo_test_#{id}")
    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Create a mock session state.
  """
  def mock_session_state(opts \\ []) do
    now = DateTime.utc_now()
    merged = merge_with_defaults(opts)

    %Albedo.Session.State{
      id: merged.id,
      codebase_path: merged.codebase_path,
      task: merged.task,
      state: merged.state,
      created_at: now,
      updated_at: now,
      session_dir: merged.session_dir,
      config: merged.config,
      phases: init_phases(opts[:phases] || %{}),
      context: merged.context,
      clarifying_questions: merged.clarifying_questions,
      summary: opts[:summary]
    }
  end

  defp merge_with_defaults(opts) do
    %{
      id: Keyword.get(opts, :id, "test-session-#{:rand.uniform(999)}"),
      codebase_path: Keyword.get(opts, :codebase_path, "/tmp/test_codebase"),
      task: Keyword.get(opts, :task, "Test task description"),
      state: Keyword.get(opts, :state, :created),
      session_dir: Keyword.get(opts, :session_dir, tmp_session_dir()),
      config: Keyword.get(opts, :config, %{}),
      context: Keyword.get(opts, :context, %{}),
      clarifying_questions: Keyword.get(opts, :clarifying_questions, [])
    }
  end

  defp init_phases(overrides) do
    default = %{
      status: :pending,
      started_at: nil,
      completed_at: nil,
      duration_ms: nil,
      output_file: nil,
      error: nil
    }

    phases = [
      :domain_research,
      :tech_stack,
      :architecture,
      :conventions,
      :feature_location,
      :impact_analysis,
      :change_planning
    ]

    phases
    |> Enum.map(fn phase ->
      {phase, Map.merge(default, Map.get(overrides, phase, %{}))}
    end)
    |> Map.new()
  end

  @doc """
  Create a minimal test codebase fixture.
  """
  def create_test_codebase do
    dir = Path.join(System.tmp_dir!(), "albedo_test_codebase_#{:rand.uniform(999)}")
    File.mkdir_p!(Path.join(dir, "lib/my_app"))
    File.mkdir_p!(Path.join(dir, "test"))

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project

      def project do
        [
          app: :my_app,
          version: "0.1.0",
          elixir: "~> 1.15",
          deps: deps()
        ]
      end

      def application do
        [extra_applications: [:logger]]
      end

      defp deps do
        [
          {:phoenix, "~> 1.7"},
          {:ecto, "~> 3.11"}
        ]
      end
    end
    """)

    File.write!(Path.join([dir, "lib", "my_app", "orders.ex"]), """
    defmodule MyApp.Orders do
      alias MyApp.Orders.Order

      def list_orders do
        []
      end

      def get_order(id) do
        nil
      end
    end
    """)

    File.write!(Path.join([dir, "lib", "my_app", "order.ex"]), """
    defmodule MyApp.Orders.Order do
      use Ecto.Schema

      schema "orders" do
        field :status, :string
        field :total, :decimal
        timestamps()
      end
    end
    """)

    dir
  end

  @doc """
  Clean up test files.
  """
  def cleanup(path) do
    File.rm_rf!(path)
  end
end
