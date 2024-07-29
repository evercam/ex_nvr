defmodule ExNVR.Umbrella.MixProject do
  use Mix.Project

  @version "0.14.0"

  def project do
    [
      apps_path: "apps",
      version: @version,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  defp deps do
    [
      # Required to run "mix format" on ~H/.heex files from the umbrella root
      {:phoenix_live_view, ">= 0.0.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  def releases() do
    [
      ex_nvr: [
        version: @version,
        applications: [ex_nvr: :permanent, ex_nvr_web: :permanent],
        include_executables_for: [:unix],
        steps: steps()
      ]
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  #
  # Aliases listed here are available only for this project
  # and cannot be accessed from applications inside the apps/ folder.
  defp aliases do
    [
      # run `mix setup` in all child apps
      setup: ["cmd mix setup"],
      release: ["cmd --app ex_nvr_web mix release", "release"]
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
          libs ++
            [
              "/usr/lib/#{arch}-linux-#{abi}/libavcodec.so*",
              "/usr/lib/#{arch}-linux-#{abi}/libavformat.so*",
              "/usr/lib/#{arch}-linux-#{abi}/libavutil.so*",
              "/usr/lib/#{arch}-linux-#{abi}/libavfilter.so*",
              "/usr/lib/#{arch}-linux-#{abi}/libavresample.so*"
            ]

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

      File.mkdir!(dest)
      File.mkdir_p!(Path.join([dest, "opt", "ex_nvr"]))
      File.mkdir_p!(Path.join([dest, "var", "lib", "ex_nvr"]))
      File.mkdir_p!(Path.join([dest, "usr", "lib", "systemd", "system"]))
      File.mkdir_p!(Path.join(dest, "DEBIAN"))

      File.cp_r!(release.path, Path.join([dest, "opt", "ex_nvr"]))

      File.write!(Path.join([dest, "DEBIAN", "control"]), """
      Package: ex-nvr
      Version: #{release.version}
      Architecture: #{get_debian_arch(arch)}
      Maintainer: Evercam <support@evercam.io>
      Description: NVR (Network Video Recorder) software for Elixir.
      Homepage: https://github.com/evercam/ex_nvr
      """)

      File.write!(Path.join([dest, "usr", "lib", "systemd", "system", "ex_nvr.service"]), """
      [Unit]
      Description=ExNVR: Network Video Recorder
      After=network.target

      [Service]
      Type=simple
      User=root
      Group=root
      ExecStart=/opt/ex_nvr/run
      Restart=always
      RestartSec=1
      SyslogIdentifier=ex_nvr
      WorkingDirectory=/opt/ex_nvr
      LimitNOFILE=8192

      [Install]
      WantedBy=multi-user.target
      """)

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
    [architecture, _vendor, os, abi] =
      :erlang.system_info(:system_architecture)
      |> List.to_string()
      |> String.split("-")

    {architecture, os, abi}
  end

  defp get_debian_arch("x86_64"), do: "amd64"
  defp get_debian_arch("aarch64"), do: "arm64"
  defp get_debian_arch("arm"), do: "armhf"
end
