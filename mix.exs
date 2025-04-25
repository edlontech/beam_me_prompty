defmodule BeamMePrompty.MixProject do
  use Mix.Project

  def project do
    [
      app: :beam_me_prompty,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:gen_state_machine, "~> 3.0"},
      {:hammox, "~> 0.7", only: :test},
      {:jungle_spec, "~> 0.1.1"},
      {:nimble_options, "~> 1.1"},
      {:plug, "~> 1.7"},
      {:req, "~> 0.5"},
      {:splode, "~> 0.2"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
