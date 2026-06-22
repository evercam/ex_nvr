defmodule NvrSupport.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :nvr_support,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # No `mod:` on purpose - nvr_support must NOT auto-start a supervisor. The
  # Nerves firmware apps start `{NvrSupport, []}` themselves, and only on
  # non-host targets where Erlang's `-heart` is active.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Synthetic-alarm engine that drives the watchdog. Its OTP app starts
      # automatically wherever nvr_support is a dependency.
      {:alarmist, "~> 0.4"}
    ]
  end
end
