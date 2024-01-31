defmodule ExNVR.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_nvr,
      version: "0.9.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {ExNVR.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:native, in_umbrella: true},
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.6"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:jason, "~> 1.2"},
      {:swoosh, "~> 1.15"},
      {:finch, "~> 0.13"},
      {:ex_sdp, "~> 0.14.0", override: true},
      {:membrane_core, "~> 1.0"},
      {:membrane_rtsp, "~> 0.5.3"},
      {:membrane_rtp_plugin, "~> 0.24.0"},
      {:membrane_rtp_h264_plugin, "~> 0.19.0"},
      {:membrane_rtp_h265_plugin, "~> 0.5.0"},
      {:membrane_h264_plugin, "~> 0.9.0"},
      {:membrane_h265_plugin, "~> 0.4.0"},
      {:membrane_mp4_plugin, "~> 0.31.0"},
      {:membrane_file_plugin, "~> 0.16.0"},
      {:membrane_http_adaptive_stream_plugin, "~> 0.18.0"},
      {:membrane_h264_ffmpeg_plugin, "~> 0.31.0"},
      {:membrane_h265_ffmpeg_plugin, "~> 0.4.0"},
      {:membrane_ffmpeg_swscale_plugin, "~> 0.15.0"},
      {:membrane_realtimer_plugin, "~> 0.9.0"},
      {:membrane_rtc_engine, "~> 0.20.0"},
      {:membrane_rtc_engine_webrtc, "~> 0.6.0"},
      {:membrane_fake_plugin, "~> 0.11.0"},
      {:ex_libsrtp, "~> 0.7.0"},
      {:membrane_udp_plugin, "~> 0.12.0"},
      {:connection, "~> 1.1.0"},
      {:tzdata, "~> 1.1"},
      {:turbojpeg, "~> 0.4.0"},
      {:flop, "~> 0.22.1"},
      {:soap, github: "gBillal/soap", branch: "parse-attributes"},
      {:faker, "~> 0.17", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
