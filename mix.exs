defmodule BeamMePrompty.MixProject do
  use Mix.Project

  def project do
    [
      app: :beam_me_prompty,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      source_url: "https://github.com/edlontech/beam_me_prompty",
      homepage_url: "https://github.com/edlontech/beam_me_prompty",
      docs: [
        main: "readme",
        extras: ["README.md", "LICENSE.md"]
      ]
    ]
  end

  def application do
    [
      mod: {BeamMePrompty, []},
      env: [],
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:gen_state_machine, "~> 3.0"},
      {:hammox, "~> 0.7", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:mustache, "~> 0.5"},
      {:nimble_options, "~> 1.1"},
      {:open_api_spex, "~> 3.21"},
      {:plug, "~> 1.7"},
      {:req, "~> 0.5"},
      {:recode, "~> 0.6", only: :dev, runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:spark, "~> 2.2.55"},
      {:splode, "~> 0.2"},
      {:typedstruct, "~> 0.5.3"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "BeamMePrompty is an Elixir library for building and executing multi-stage agents against Large Language Models (LLMs). It provides a DSL to define agent stages, manage dependencies, validate inputs/outputs, and plug in custom LLM clients."
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/edlontech/beam_me_prompty"},
      sponsor: "ycastor.eth"
    ]
  end
end
