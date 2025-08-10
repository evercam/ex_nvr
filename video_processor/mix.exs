defmodule ExNVR.VideoProcessor.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :video_processor,
      version: @version,
      elixir: "~> 1.18",
      compilers: [:elixir_make] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      make_clean: ["clean"]
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
      {:elixir_make, "~> 0.9", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    ]
  end
end
