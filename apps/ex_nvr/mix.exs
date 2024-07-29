defmodule ExNVR.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_nvr,
      version: "0.14.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
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
      {:unifex, "~> 1.1"},
      {:bundlex, "~> 1.4.6"},
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.6"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:ecto_sqlite3_extras, "~> 1.2.0"},
      {:jason, "~> 1.2"},
      {:swoosh, "~> 1.15"},
      {:finch, "~> 0.13"},
      {:ex_sdp, "~> 0.17.0", override: true},
      {:membrane_core, "~> 1.0"},
      {:membrane_rtp_plugin, "~> 0.27.1", override: true},
      {:membrane_file_plugin, "~> 0.17.0", override: true},
      {:membrane_rtsp_plugin, github: "gBillal/membrane_rtsp_plugin", branch: "fix-out-of-memory"},
      {:membrane_mp4_plugin, "~> 0.35.0", override: true},
      {:membrane_http_adaptive_stream_plugin,
       github: "gBillal/membrane_http_adaptive_stream_plugin", ref: "8f75c6b"},
      {:membrane_h264_ffmpeg_plugin, "~> 0.31.0"},
      {:membrane_h265_ffmpeg_plugin, "~> 0.4.0"},
      {:membrane_ffmpeg_swscale_plugin, "~> 0.15.0"},
      {:membrane_realtimer_plugin, "~> 0.9.0"},
      {:membrane_rtc_engine, "~> 0.21.0"},
      {:membrane_rtc_engine_webrtc, "~> 0.7.0"},
      {:membrane_fake_plugin, "~> 0.11.0"},
      {:ex_libsrtp, "~> 0.7.0"},
      {:ex_m3u8, "~> 0.14.2"},
      {:connection, "~> 1.1.0"},
      {:tzdata, "~> 1.1"},
      {:turbojpeg, "~> 0.4.0"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:flop, "~> 0.22.1"},
      {:soap, github: "gBillal/soap", branch: "parse-attributes"},
      {:req, "~> 0.4.0"},
      {:multipart, "~> 0.4.0"},
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
