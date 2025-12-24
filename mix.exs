defmodule Albedo.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/jeryldev/albedo"

  def project do
    [
      app: :albedo,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      releases: releases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Albedo",
      description: "Codebase-to-tickets CLI tool for systematic code analysis",
      package: package(),
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Albedo.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:owl, "~> 0.12"},
      {:toml, "~> 0.7"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp escript do
    [
      main_module: Albedo.CLI,
      name: "albedo"
    ]
  end

  defp releases do
    [
      albedo: [
        steps: [:assemble]
      ]
    ]
  end

  defp package do
    [
      name: "albedo",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
