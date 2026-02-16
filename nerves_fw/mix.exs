defmodule NervesFw.MixProject do
  use Mix.Project

  @app :ex_nvr_fw
  @version "0.26.1"
  @all_targets [:ex_nvr_rpi4, :ex_nvr_rpi5, :giraffe]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      archives: [nerves_bootstrap: "~> 1.13"],
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      releases: [{@app, release()}]
    ]
  end

  def cli do
    [preferred_cli_target: [run: :host, test: :host]]
  end

  def application do
    [
      mod: {ExNVR.Nerves.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    env = if Mix.env() == :prod, do: :prod, else: :dev

    [
      # Dependencies for all targets
      {:nerves, "~> 1.10", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.4.0"},
      {:nerves_hub_link, "~> 2.10.0"},
      {:nerves_hub_cli, "~> 2.0"},
      {:ex_nvr, path: "../ui", env: env},
      {:circuits_gpio, "~> 2.1"},
      {:circuits_i2c, "~> 2.0"},

      # Allow Nerves.Runtime on host to support development, testing and CI.
      # See config/host.exs for usage.
      {:nerves_runtime, "~> 0.13.0"},

      # Dependencies for all targets except :host
      {:nerves_pack, "~> 0.7.0", targets: @all_targets},
      {:mimic, "~> 2.1", only: :test},
      {:ex_nvr_system_rpi4,
       github: "evercam/ex_nvr_system_rpi4", tag: "v1.33.0", runtime: false, targets: :ex_nvr_rpi4},
      {:ex_nvr_system_rpi5,
       github: "evercam/ex_nvr_system_rpi5",
       tag: "v0.8.0",
       runtime: false,
       targets: [:ex_nvr_rpi5, :giraffe]}
    ]
  end

  def release do
    [
      overwrite: true,
      # Erlang distribution is not started automatically.
      # See https://hexdocs.pm/nerves_pack/readme.html#erlang-distribution
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end

  defp aliases do
    []
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
