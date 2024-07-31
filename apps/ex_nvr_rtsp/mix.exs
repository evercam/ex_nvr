defmodule ExNvrRtsp.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_nvr_rtsp,
      version: "0.14.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_sdp, "~> 1.0", override: true},
      {:membrane_core, "~> 1.1"},
      {:ex_rtp, "~> 0.4.0"},
      {:ex_rtcp, "~> 0.4.0"},
      {:membrane_rtsp, "~> 0.7.0"},
      {:membrane_h26x_plugin, "~> 0.10.0"},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false},
      {:mimic, "~> 1.7", only: :test}
    ]
  end
end
