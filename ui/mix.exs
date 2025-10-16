defmodule ExNVR.MixProject do
  use Mix.Project

  @app :ex_nvr
  @version "0.24.0"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      releases: [{@app, release()}],
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ExNVRWeb.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
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
      {:video_processor, path: "../video_processor"},
      {:rtsp, "~> 0.5.0"},
      {:ex_sdp, "~> 1.0"},
      {:bundlex, "~> 1.5", override: true},
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:ecto_sqlite3_extras, "~> 1.2.0"},
      {:swoosh, "~> 1.15"},
      {:finch, "~> 0.19"},
      {:httpoison, "~> 2.2.1"},
      {:membrane_h264_format, "~> 0.6"},
      {:membrane_h265_format, "~> 0.2"},
      {:membrane_raw_video_format, "~> 0.4.0", override: true},
      {:membrane_file_plugin, "~> 0.17.0"},
      {:membrane_realtimer_plugin, "~> 0.10.0"},
      {:ex_webrtc, "~> 0.14.0"},
      {:ex_libsrtp, "~> 0.7.0"},
      {:ex_m3u8, "~> 0.15.0"},
      {:connection, "~> 1.1.0"},
      {:tzdata, "~> 1.1"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:flop, "~> 0.26.0"},
      {:req, "~> 0.5.0"},
      {:multipart, "~> 0.4.0"},
      {:ex_mp4, "~> 0.12.0"},
      {:floki, "~> 0.38.0"},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8.1"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:corsica, "~> 2.1"},
      {:logger_json, "~> 7.0"},
      {:flop_phoenix, "~> 0.24"},
      {:prom_ex, "~> 1.11.0"},
      {:circuits_uart, "~> 1.5"},
      {:ex_onvif, "~> 0.7.2"},
      {:slipstream, "~> 1.2.0"},
      {:live_vue, "~> 0.5.7"},
      {:sentry, "~> 11.0"},
      {:live_debugger, "~> 0.3.0", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:phoenix_live_reload, "~> 1.2", only: [:dev, :test]},
      {:membrane_h26x_plugin, "~> 0.10", only: :test},
      {:mimic, "~> 2.1", only: :test},
      {:faker, "~> 0.17", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:lazy_html, "~> 0.1.0", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["cmd --cd assets npm install"],
      "assets.build": [
        "cmd --cd assets npm run build",
        "cmd --cd assets npm run build-server"
      ],
      "assets.deploy": [
        "cmd --cd assets npm run build",
        "phx.digest --no-compile"
      ],
      "assets.clean": [
        "phx.digest.clean --all"
      ],
      release: ["cmd --cd assets npm install", "assets.deploy", "release"]
    ]
  end

  defp release() do
    [
      version: @version,
      include_executables_for: [:unix],
      steps: steps()
    ]
  end

  defp steps() do
    if System.get_env("DOCKER_BUILD", "false") |> String.to_existing_atom() do
      [:assemble]
    else
      release_steps(get_target())
    end
  end

  defp release_steps({arch, "linux", abi}) do
    [
      :assemble,
      &copy_external_libs(&1, {arch, abi}),
      &archive/1,
      &generate_deb_package(&1, {arch, abi})
    ]
  end

  defp release_steps(_other), do: [:assemble]

  defp copy_external_libs(release, {arch, abi}) do
    libs_dest = Path.join(release.path, "external_lib")

    unless File.exists?(libs_dest) do
      File.mkdir_p!(libs_dest)
    end

    # Tried to use `File.cp` to copy dependencies however links are not copied correctly
    # which made the size of the destination folder 3 times the original size.
    libs = [
      "/usr/lib/#{arch}-linux-#{abi}/libsrtp2.so*",
      "/usr/lib/#{arch}-linux-#{abi}/libssl.so*",
      "/usr/lib/#{arch}-linux-#{abi}/libcrypto.so*"
    ]

    System.shell("cp -P #{Enum.join(libs, " ")} #{libs_dest}")
    release
  end

  defp archive(release) do
    # Same thing happened when using `:tar` step, links are not copied correctly
    # which made the size of the tar ball big.
    {arch, os, abi} = get_target()
    filename = "#{release.name}-v#{release.version}-#{arch}-unknown-#{os}-#{abi}.tar.gz"
    dest = Path.expand("../..", release.path)

    System.cmd("tar", [
      "-czvf",
      Path.join(dest, filename),
      "-C",
      Path.expand("..", release.path),
      "#{release.name}"
    ])

    release
  end

  defp generate_deb_package(release, {arch, _abi}) do
    generate_deb? = System.get_env("GENERATE_DEB_PACKAGE", "false") |> String.to_existing_atom()

    if generate_deb? do
      name = "ex-nvr_#{release.version}-1_#{get_debian_arch(arch)}"
      pkg_dest = Path.expand("../..", release.path)
      dest = Path.join(pkg_dest, name)

      File.rm_rf!(dest)

      # Create folder structure
      File.mkdir!(dest)
      File.mkdir_p!(Path.join([dest, "opt", "ex_nvr"]))
      File.mkdir_p!(Path.join([dest, "var", "lib", "ex_nvr"]))
      File.mkdir_p!(Path.join([dest, "usr", "lib", "systemd", "system"]))
      File.mkdir_p!(Path.join(dest, "DEBIAN"))

      File.cp_r!(release.path, Path.join([dest, "opt", "ex_nvr"]))

      # control file
      Path.join([templates_dir(), "debian", "control.eex"])
      |> EEx.eval_file(assigns: %{version: release.version, arch: get_debian_arch(arch)})
      |> then(&File.write!(Path.join([dest, "DEBIAN", "control"]), &1))

      # systemd service
      dest = Path.join([dest, "usr", "lib", "systemd", "system", "ex_nvr.service"])
      Path.join([templates_dir(), "debian", "ex_nvr.service"]) |> File.cp!(dest)

      {_result, 0} =
        System.cmd("dpkg-deb", ["--root-owner-group", "--build", name],
          stderr_to_stdout: true,
          cd: pkg_dest
        )

      release
    else
      release
    end
  end

  defp get_target() do
    :erlang.system_info(:system_architecture)
    |> List.to_string()
    |> String.split("-")
    |> case do
      [architecture, _vendor, os, abi] ->
        {architecture, os, abi}

      [architecture, _vendor, os] ->
        {architecture, os, nil}
    end
  end

  defp get_debian_arch("x86_64"), do: "amd64"
  defp get_debian_arch("aarch64"), do: "arm64"
  defp get_debian_arch("arm"), do: "armhf"

  defp templates_dir(), do: :code.priv_dir(:ex_nvr) |> List.to_string()
end
