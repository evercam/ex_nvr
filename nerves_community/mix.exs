defmodule ExNVR.Nerves.MixProject do
  use Mix.Project

  @app :exnvr_fw
  @version "0.26.1"
  @all_targets [:rpi4, :rpi5, :qemu_aarch64]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      archives: [nerves_bootstrap: "~> 1.14"],
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      releases: [{@app, release()}]
    ]
  end

  def cli do
    [
      # test.qemu is a custom task, so tell mix to run it in :test on host.
      preferred_envs: ["test.qemu": :test],
      preferred_targets: [run: :host, test: :host, "test.qemu": :host]
    ]
  end

  # The QEMU resilience-test harness (test/support) is host-only.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Convenience: `mix test.qemu` == `mix test --no-start --only qemu`. --no-start
  # keeps the heavy :ex_nvr app from booting on the host (the harness only drives
  # the guest VM).
  defp aliases do
    ["test.qemu": ["test --no-start --only qemu"]]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {ExNVR.Nerves.Application, []}
    ]
  end

  defp deps do
    env = if Mix.env() == :prod, do: :prod, else: :dev

    [
      {:nerves, "~> 1.10", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.4.0"},
      {:nerves_runtime, "~> 0.13.0"},
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},
      {:ex_nvr, path: "../ui", env: env},
      {:nvr_support, path: "../nvr_support"},
      {:circuits_gpio, "~> 2.1"},
      {:circuits_i2c, "~> 2.0"},
      {:ex_nvr_system_rpi4,
       github: "evercam/ex_nvr_system_rpi4", tag: "v1.33.0", runtime: false, targets: :rpi4},
      {:ex_nvr_system_rpi5,
       github: "evercam/ex_nvr_system_rpi5", tag: "v0.8.0", runtime: false, targets: [:rpi5]},
      # QEMU VM target for running experiments (e.g. the watchdog) without
      # hardware. Resolves the prebuilt system artifact from the evercam release
      # (matched by checksum via the system's github_releases artifact_site),
      # pinned to the v0.3.8 commit for reproducibility.
      {:ex_nvr_system_qemu_aarch64,
       github: "evercam/ex_nvr_system_qemu_aarch64",
       ref: "c5a2193f0de9292925b6e8efa50785778c6d8653",
       runtime: false,
       targets: :qemu_aarch64},
      # Drives the QEMU guest over an Erlang :peer RPC channel on the serial
      # console for VM-based resilience tests. Needed in the qemu firmware (the
      # guest's `-user peer`) AND on the host (the test harness runs it as the
      # bridge); not in the rpi firmwares.
      {:peer_bridge,
       github: "fhunleth/peer_bridge",
       ref: "84cedb60ca74a965081c4c13a0499c7e0c6e5979",
       targets: [:host, :qemu_aarch64]}
    ]
  end

  def release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, &install_peer_bridge/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end

  # Symlink the versioned peer_bridge binary to a fixed path so erlinit's
  # alternate_exec (config/qemu_aarch64.exs) can launch it before the BEAM
  # starts. No-op on targets that don't include peer_bridge (rpi4/rpi5).
  defp install_peer_bridge(release) do
    case release.applications[:peer_bridge] do
      nil ->
        release

      app ->
        bin_dir = Path.join(release.path, "bin")
        File.mkdir_p!(bin_dir)
        target = Path.join(bin_dir, "peer_bridge")
        source = Path.join(["..", "lib", "peer_bridge-#{app[:vsn]}", "priv", "peer_bridge"])
        _ = File.rm(target)
        File.ln_s!(source, target)
        release
    end
  end
end
