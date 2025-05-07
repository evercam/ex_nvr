defmodule ExNVR.MixProject do
  Code.require_file("mix/utils.exs", __DIR__)

  use Mix.Project

  @app :ex_nvr
  @version "0.20.0"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      releases: [{@app, release()}],
      deps: deps()
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
  defp elixirc_paths(:test), do: ["lib", "test/support"] ++ ExNVR.Mix.Utils.plugin_paths()
  defp elixirc_paths(_), do: ["lib"] ++ ExNVR.Mix.Utils.plugin_paths()

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ex_nvr_rtsp, path: "../rtsp"},
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
      {:membrane_raw_video_format, "~> 0.4.0", override: true},
      {:membrane_file_plugin, "~> 0.17.0"},
      {:membrane_mp4_plugin, "~> 0.35.0"},
      {:membrane_http_adaptive_stream_plugin, "~> 0.18.0"},
      {:membrane_h264_ffmpeg_plugin, "~> 0.32.0"},
      {:membrane_h265_ffmpeg_plugin, "~> 0.4.0"},
      {:membrane_ffmpeg_swscale_plugin, "~> 0.16.0"},
      {:membrane_realtimer_plugin, "~> 0.10.0"},
      {:ex_webrtc, "~> 0.8.0"},
      {:ex_libsrtp, "~> 0.7.0"},
      {:ex_m3u8, "~> 0.15.0"},
      {:connection, "~> 1.1.0"},
      {:tzdata, "~> 1.1"},
      {:turbojpeg, "~> 0.4.0"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:flop, "~> 0.26.0"},
      {:req, "~> 0.5.0"},
      {:multipart, "~> 0.4.0"},
      {:ex_mp4, "~> 0.9.0"},
      {:floki, "~> 0.37.0"},
      {:phoenix, "~> 1.7.2"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
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
      {:reverse_proxy_plug, "~> 3.0"},
      {:circuits_uart, "~> 1.5"},
      {:onvif, github: "gBillal/onvif", tag: "v0.6.0"},
      {:slipstream, "~> 1.2.0"},
      {:live_vue, "~> 0.5.7"},
      {:sentry, "~> 10.9"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.11.0", only: :test},
      {:faker, "~> 0.17", only: :test},
      {:bypass, "~> 2.1", only: :test}
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
        "phx.digest"
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

  defp release_steps({arch, "linux", "gnu"}) do
    [
      &delete_wrong_symlink/1,
      :assemble,
      &copy_ffmpeg_deps/1,
      &copy_external_libs(&1, {arch, "gnu"}),
      &archive/1,
      &generate_deb_package(&1, {arch, "gnu"})
    ]
  end

  defp release_steps({"arm", "linux", "gnueabihf"}) do
    arch = {"arm", "gnueabihf"}

    [
      :assemble,
      &copy_external_libs(&1, arch),
      &archive/1,
      &generate_deb_package(&1, arch)
    ]
  end

  defp release_steps(_other), do: [:assemble]

  defp delete_wrong_symlink(release) do
    Path.join([Application.app_dir(:ex_nvr), "priv", "bundlex", "nif", "*"])
    |> Path.wildcard()
    |> Enum.reject(&File.exists?/1)
    |> Enum.each(&File.rm!/1)

    release
  end

  defp copy_ffmpeg_deps(release) do
    libs_dest = Path.join(release.path, "external_lib")
    File.mkdir_p!(libs_dest)

    suffix_path = Path.join(["priv", "shared", "precompiled"])
    src_bundlex_path = Path.join(Application.app_dir(:bundlex), suffix_path)

    System.shell("cp -P #{Path.join([src_bundlex_path, "**", "lib", "*.so*"])} #{libs_dest}")

    dest_bundlex_path =
      Path.join([release.path, "lib", "bundlex*", suffix_path])
      |> Path.wildcard()
      |> List.first()

    deps = File.ls!(src_bundlex_path)

    Application.loaded_applications()
    |> Enum.map(fn {name, _path, _version} -> name end)
    |> Enum.map(fn dep ->
      [release.path, "lib", "#{dep}-*", "priv", "bundlex", "nif"]
      |> Path.join()
      |> Path.wildcard()
      |> List.first()
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.each(fn dest ->
      Enum.each(deps, fn dep ->
        File.rm_rf(Path.join(dest, dep))
        File.rm_rf(Path.join(dest, dep <> "_physical"))
      end)
    end)

    File.rm_rf!(dest_bundlex_path)

    release
  end

  defp copy_external_libs(release, {arch, abi}) do
    libs_dest = Path.join(release.path, "external_lib")

    unless File.exists?(libs_dest) do
      File.mkdir_p!(libs_dest)
    end

    # Tried to use `File.cp` to copy dependencies however links are not copied correctly
    # which made the size of the destination folder 3 times the original size.
    libs = [
      "/usr/lib/#{arch}-linux-#{abi}/libsrtp2.so*",
      "/usr/lib/#{arch}-linux-#{abi}/libturbojpeg.so*",
      "/usr/lib/#{arch}-linux-#{abi}/libssl.so*",
      "/usr/lib/#{arch}-linux-#{abi}/libcrypto.so*"
    ]

    libs =
      case arch do
        "arm" ->
          {libdir, 0} =
            System.cmd("pkg-config", ["--variable=libdir", "libavformat"], stderr_to_stdout: true)

          [
            "libavcodec.so*",
            "libavformat.so*",
            "libavutil.so*",
            "libavfilter.so*",
            "libswresample.so*",
            "libswscale.so*"
          ]
          |> Enum.map(&Path.join(String.trim(libdir), &1))
          |> Kernel.++(libs)

        _other ->
          libs
      end

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
