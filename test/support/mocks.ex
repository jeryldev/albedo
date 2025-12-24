defmodule Albedo.TestSupport.Mocks do
  @moduledoc """
  Test mocks and helpers for Albedo tests.
  """

  @doc """
  Mock LLM response for testing agents.
  """
  def mock_llm_response(response) do
    {:ok, response}
  end

  @doc """
  Creates a temporary directory for testing.
  """
  def create_temp_dir do
    dir = Path.join(System.tmp_dir!(), "albedo_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Creates a sample codebase for testing.
  """
  def create_sample_codebase(base_dir) do
    File.mkdir_p!(Path.join(base_dir, "lib"))
    File.mkdir_p!(Path.join(base_dir, "test"))

    File.write!(Path.join(base_dir, "mix.exs"), """
    defmodule SampleApp.MixProject do
      use Mix.Project

      def project do
        [
          app: :sample_app,
          version: "0.1.0",
          elixir: "~> 1.15",
          deps: deps()
        ]
      end

      defp deps do
        []
      end
    end
    """)

    File.write!(Path.join([base_dir, "lib", "sample_app.ex"]), """
    defmodule SampleApp do
      @moduledoc "Sample application module."

      def hello do
        :world
      end
    end
    """)

    File.write!(Path.join([base_dir, "test", "sample_app_test.exs"]), """
    defmodule SampleAppTest do
      use ExUnit.Case

      test "hello returns world" do
        assert SampleApp.hello() == :world
      end
    end
    """)

    base_dir
  end

  @doc """
  Cleans up a temporary directory.
  """
  def cleanup_temp_dir(dir) do
    File.rm_rf!(dir)
  end

  @doc """
  Captures IO output from a function.
  """
  def capture_io(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
