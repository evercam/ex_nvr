defmodule ExNvrRtsp.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_nvr_rtsp,
      version: "0.18.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_sdp, "~> 1.0", override: true},
      {:membrane_core, "~> 1.1"},
      {:ex_rtp, "~> 0.4.0"},
      {:ex_rtcp, "~> 0.4.0"},
      {:membrane_rtsp, "~> 0.10.0"},
      {:membrane_h26x_plugin, "~> 0.10.0"},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false},
      {:mimic, "~> 1.7", only: :test}
    ]
  end
end
