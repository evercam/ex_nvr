defmodule ExNVR.Umbrella.MixProject do
  use Mix.Project

  @version "0.5.1"

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
        steps: [:assemble, &copy_external_libs/1, &archive/1]
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
      setup: ["cmd mix setup"]
    ]
  end

  defp copy_external_libs(release) do
    case get_target() do
      {arch, "linux", "gnu"} ->
        libs_dest = Path.join(release.path, "external_lib")
        File.mkdir!(libs_dest)
        copy_libs(arch, libs_dest)
        release

      _other ->
        release
    end
  end

  defp copy_libs(arch, dest_dir) do
    # Tried to use `File.cp` to copy dependencies however links are not copied correctly
    # which made the size of the destination folder 3 times the orginal size.
    src_1 = Path.join(["_build", "#{Mix.env()}", "bundlex_precompiled", "**", "lib", "*.so*"])
    src_2 = "/lib/#{arch}-linux-gnu/libsrtp2.so*"
    src_3 = "/lib/#{arch}-linux-gnu/libturbojpeg.so*"

    System.shell("cp -P #{src_1} #{src_2} #{src_3} #{dest_dir}")
  end

  defp archive(release) do
    # Same thing happened when using `:tar` step, links are not copied correctly
    # which made the size of the tar ball big.
    {arch, os, abi} = get_target()
    filename = "#{release.name}-#{release.version}-#{arch}-unknown-#{os}-#{abi}.tar.gz"
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

  defp get_target() do
    [architecture, _vendor, os, abi] =
      :erlang.system_info(:system_architecture)
      |> List.to_string()
      |> String.split("-")

    {architecture, os, abi}
  end
end
