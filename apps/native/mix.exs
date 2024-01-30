defmodule Native.MixProject do
  use Mix.Project

  def project do
    [
      app: :native,
      version: "0.9.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
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
      {:unifex, "~> 1.1"},
      {:bundlex, "~> 1.4"},
      {:membrane_precompiled_dependency_provider, "~> 0.1"}
    ]
  end
end
