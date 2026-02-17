defmodule ExNVR.Nerves.MixProject do
  use Mix.Project

  @app :exnvr_fw
  @version "0.26.1"
  @all_targets [:rpi4, :rpi5]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      archives: [nerves_bootstrap: "~> 1.14"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}],
      preferred_cli_target: [run: :host, test: :host]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {ExNVR.Nerves.Application, []}
    ]
  end

  defp deps do
    env = if Mix.env() == :prod, do: :prod, else: :dev

    [
      {:nerves, "~> 1.10", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.4.0"},
      {:nerves_runtime, "~> 0.13.0"},
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},
      {:ex_nvr, path: "../ui", env: env},
      {:circuits_gpio, "~> 2.1"},
      {:circuits_i2c, "~> 2.0"},
      {:ex_nvr_system_rpi4,
       github: "evercam/ex_nvr_system_rpi4", tag: "v1.33.0", runtime: false, targets: :rpi4},
      {:ex_nvr_system_rpi5,
       github: "evercam/ex_nvr_system_rpi5", tag: "v0.8.0", runtime: false, targets: [:rpi5]}
    ]
  end

  def release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end
end
