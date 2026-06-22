defmodule ExNVR.QemuTest.VM do
  @moduledoc """
  Boot and control a Nerves firmware image under QEMU for fault-injection tests.

  A VM is launched from the built `.fw` (turned into a disk image with `fwup`,
  exactly like `mix nerves.gen.qemu`). It exposes three outside control surfaces:

    * **`:peer` RPC** (`call/4`, `cmd/3`) - the guest is an Erlang `:peer` node
      reachable over the serial console via `peer_bridge`. `call/4` runs any MFA
      in the guest and returns real Erlang terms; no in-guest agent and no text
      scraping. This works without guest networking (the network is something we
      fault-inject), so it stays up while we degrade the network.
    * **QMP** (`qmp/3`) - live virtual-device / network manipulation.
    * **The host process** - `power_off/1` SIGKILLs QEMU to model sudden power
      loss; `shutdown/1` SIGTERMs it (clean). The disk image persists so the VM
      can be `boot_again/1`.

  An optional secondary "data" disk (`/dev/vdb`) can be attached as a fault
  target so disk faults don't take down the rootfs. It can be wrapped in
  `blkdebug` to inject I/O errors.

  ## How the control channel is wired

      host test --:peer.call--> :peer (origin)
                                | stdin/stdout (raw Erlang distribution)
      host peer_bridge --raw-to-link
                                | framed bytes over the QEMU serial (stdio)
      qemu-system-aarch64  -- QMP tcp (faults) <-- host
                                | ttyAMA0
      guest peer_bridge (erlinit alternate_exec, appends -user peer)
                                | raw Erlang distribution
      guest BEAM (-user peer) -- runs the app

  `:peer` would normally append `-user peer`/name args meant for an `erl` child;
  those would land on QEMU, so we rewrite the spawned argv with
  `post_process_args`. QEMU's own stderr is redirected to a log file so it can't
  corrupt the distribution stream that shares QEMU's stdout.
  """

  alias ExNVR.QemuTest.QMP

  @default_boot_timeout 120_000

  defstruct [
    :peer,
    :qmp,
    :disk,
    :data_disk,
    :data_fault,
    :work_dir,
    :qemu_log,
    :fw_path,
    :sdk_images,
    :ssh_port,
    :qmp_port,
    :ram,
    :smp,
    :boot_timeout,
    running: false
  ]

  @type t :: %__MODULE__{}

  @doc """
  Boot a VM and wait until the guest `:peer` node is reachable.

  Options:
    * `:fw_path` / `:sdk_images` - default to the `FW_PATH` / `NERVES_SDK_IMAGES`
      environment variables (set by `bin/qemu-test`).
    * `:ram` (default `"2G"` - ex_nvr's stack OOMs at 256M), `:smp` (default `1`).
    * `:data_disk` - `%{size: "256M", fault: :blkdebug | nil}` to attach `/dev/vdb`.
    * `:boot_timeout` (ms).
  """
  @spec boot(keyword()) :: t()
  def boot(opts \\ []) do
    fw_path = opts[:fw_path] || System.get_env("FW_PATH") || raise_missing("FW_PATH", :fw_path)

    sdk_images =
      opts[:sdk_images] || System.get_env("NERVES_SDK_IMAGES") ||
        raise_missing("NERVES_SDK_IMAGES", :sdk_images)

    loader = Path.join(sdk_images, "little_loader.elf")
    File.exists?(loader) || raise "little_loader.elf not found at #{loader}"

    peer_bridge = peer_bridge_binary()

    work_dir = opts[:work_dir] || Path.join(System.tmp_dir!(), "rt-vm-#{token()}")
    File.mkdir_p!(work_dir)

    disk = opts[:disk] || create_primary_disk(fw_path, Path.join(work_dir, "disk.img"))
    {data_disk, data_fault, data_args} = setup_data_disk(opts[:data_disk], work_dir)

    ssh_port = free_port()
    qmp_port = free_port()
    qemu_log = Path.join(work_dir, "qemu.log")

    {machine, cpu} = accel()
    ram = opts[:ram] || "2G"
    smp = opts[:smp] || 1
    qemu = System.find_executable("qemu-system-aarch64") || raise "qemu-system-aarch64 not found"

    qemu_args =
      [
        "-machine", machine,
        "-cpu", cpu,
        "-smp", to_string(smp),
        "-m", ram,
        "-kernel", loader,
        "-netdev", "user,id=eth0,hostfwd=tcp:127.0.0.1:#{ssh_port}-:22",
        "-device", "virtio-net-device,netdev=eth0,mac=fe:db:ed:de:d0:01",
        "-global", "virtio-mmio.force-legacy=false",
        "-drive", "if=none,file=#{disk},format=raw,id=vdisk",
        "-device", "virtio-blk-device,drive=vdisk,bus=virtio-mmio-bus.0",
        "-device", "virtio-balloon-device",
        "-qmp", "tcp:127.0.0.1:#{qmp_port},server,nowait",
        "-serial", "stdio",
        "-monitor", "none",
        "-display", "none"
      ] ++ data_args

    # The guest serial shares QEMU's stdout with the distribution stream, so send
    # QEMU's diagnostics to a log file instead. `exec` replaces the shell with
    # QEMU so it is peer_bridge's direct child (and findable for power-off).
    shell_cmd = "exec #{shell_join([qemu | qemu_args])} 2> #{shell_quote(qemu_log)}"
    chain = ["--raw-to-link", "--", "/bin/sh", "-c", shell_cmd]

    vm = %__MODULE__{
      disk: disk,
      data_disk: data_disk,
      data_fault: data_fault,
      work_dir: work_dir,
      qemu_log: qemu_log,
      fw_path: fw_path,
      sdk_images: sdk_images,
      ssh_port: ssh_port,
      qmp_port: qmp_port,
      ram: ram,
      smp: smp,
      boot_timeout: opts[:boot_timeout] || @default_boot_timeout
    }

    try do
      peer = start_peer(peer_bridge, chain, qmp_port, vm.boot_timeout)
      qmp = connect_qmp(qmp_port)
      %{vm | peer: peer, qmp: qmp, running: true}
    rescue
      e ->
        _ = terminate(vm, "KILL")

        log = if File.exists?(qemu_log), do: File.read!(qemu_log), else: "(no qemu log)"
        reraise Exception.message(e) <> "\n--- qemu.log ---\n#{log}", __STACKTRACE__
    end
  end

  @doc "Run an MFA in the guest and return the result term."
  @spec call(t(), module(), atom(), list(), timeout()) :: term()
  def call(%__MODULE__{peer: peer}, mod, fun, args, timeout \\ 60_000) do
    :peer.call(peer, mod, fun, args, timeout)
  end

  @doc """
  Run a shell command in the guest, returning `{output, exit_status}` (via
  `System.cmd/3` over RPC).
  """
  @spec cmd(t(), String.t(), timeout()) :: {binary(), integer()}
  def cmd(%__MODULE__{peer: peer}, command, timeout \\ 120_000) do
    :peer.call(peer, System, :cmd, ["/bin/sh", ["-c", command], [stderr_to_stdout: true]], timeout)
  end

  @doc "Run a QMP command, returning `{:ok, result}` or `{:error, reason}`."
  @spec qmp(t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def qmp(%__MODULE__{qmp: qmp}, command, arguments \\ %{}),
    do: QMP.execute(qmp, command, arguments)

  @doc "Run a QMP command, raising on error."
  @spec qmp!(t(), String.t(), map()) :: term()
  def qmp!(%__MODULE__{qmp: qmp}, command, arguments \\ %{}),
    do: QMP.execute!(qmp, command, arguments)

  @doc """
  Wait for the guest to reset/reboot itself (observed as a QMP `RESET` event) -
  e.g. the watchdog stopping the heartbeat so nerves_heart reboots the device.
  Returns `true` if it rebooted within `timeout`, `false` otherwise.
  """
  @spec await_reset(t(), timeout()) :: boolean()
  def await_reset(%__MODULE__{qmp: qmp}, timeout \\ 120_000) do
    match?({:ok, _}, QMP.wait_event(qmp, "RESET", timeout))
  end

  @doc """
  Model sudden power loss: SIGKILL the QEMU process so its volatile caches are
  lost, like yanking power. The disk image persists; use `boot_again/1`.
  """
  @spec power_off(t()) :: t()
  def power_off(vm), do: terminate(vm, "KILL")

  @doc "Cleanly stop QEMU via SIGTERM (flushes caches before exit)."
  @spec shutdown(t()) :: t()
  def shutdown(vm), do: terminate(vm, "TERM")

  @doc "Boot again on the same disk image (process must already be stopped)."
  @spec boot_again(t(), keyword()) :: t()
  def boot_again(%__MODULE__{} = vm, opts \\ []) do
    data_disk = if vm.data_disk, do: %{path: vm.data_disk, fault: vm.data_fault}, else: nil

    boot(
      Keyword.merge(
        [
          fw_path: vm.fw_path,
          sdk_images: vm.sdk_images,
          ram: vm.ram,
          smp: vm.smp,
          boot_timeout: vm.boot_timeout,
          work_dir: vm.work_dir,
          disk: vm.disk,
          data_disk: data_disk
        ],
        opts
      )
    )
  end

  @doc "Graceful reboot: `shutdown/1` then `boot_again/1`."
  @spec reboot(t(), keyword()) :: t()
  def reboot(vm, opts \\ []), do: vm |> shutdown() |> boot_again(opts)

  @doc "Stop the VM (if running) and remove its working files."
  @spec destroy(t()) :: :ok
  def destroy(%__MODULE__{} = vm) do
    if vm.running, do: power_off(vm)
    if vm.work_dir, do: File.rm_rf(vm.work_dir)
    :ok
  end

  # --- internals ---

  # Boot is retried a few times: bringing up the :peer node over the serial link
  # can race (the guest must boot far enough for its peer_bridge to start framing
  # before the origin gives up). Each failed attempt leaves a QEMU process behind,
  # so kill it before retrying.
  @boot_attempts 3

  defp start_peer(peer_bridge, chain, qmp_port, boot_timeout, attempt \\ 1) do
    case try_start_peer(peer_bridge, chain, boot_timeout) do
      {:ok, peer} ->
        peer

      {:error, reason} ->
        kill_qemu(qmp_port)

        if attempt < @boot_attempts do
          start_peer(peer_bridge, chain, qmp_port, boot_timeout, attempt + 1)
        else
          raise "peer/qemu boot failed after #{@boot_attempts} attempts: #{inspect(reason)}"
        end
    end
  end

  defp try_start_peer(peer_bridge, chain, boot_timeout) do
    result =
      :peer.start(%{
        connection: :standard_io,
        exec: {String.to_charlist(peer_bridge), []},
        post_process_args: fn _appended -> chain end,
        wait_boot: boot_timeout
      })

    case result do
      {:ok, peer} -> {:ok, peer}
      {:ok, peer, _node} -> {:ok, peer}
      {:error, reason} -> {:error, reason}
    end
  catch
    # :peer.start exits (not raises) on boot failure.
    :exit, reason -> {:error, reason}
  end

  defp terminate(%__MODULE__{running: false} = vm, _signal), do: vm

  defp terminate(%__MODULE__{} = vm, signal) do
    case qemu_pid(vm.qmp_port) do
      nil -> :ok
      pid -> System.cmd("kill", ["-#{signal}", to_string(pid)], stderr_to_stdout: true)
    end

    # Killing QEMU drops the serial link, so the peer control process terminates
    # on its own (its port gets an exit_status). We deliberately don't call
    # :peer.stop/1 - on an already-dead peer it exits with `no process`, and
    # since :peer links the control process that would crash the caller.
    if vm.qmp, do: safe(fn -> QMP.close(vm.qmp) end)

    %{vm | running: false, peer: nil, qmp: nil}
  end

  defp kill_qemu(qmp_port) do
    case qemu_pid(qmp_port) do
      nil -> :ok
      pid -> System.cmd("kill", ["-KILL", to_string(pid)], stderr_to_stdout: true)
    end
  end

  # Find the QEMU process by its unique QMP port. peer_bridge's argv also
  # contains the port string, so filter to the process whose command is qemu.
  defp qemu_pid(qmp_port) do
    marker = "tcp:127.0.0.1:#{qmp_port},server"

    case System.cmd("pgrep", ["-f", marker], stderr_to_stdout: true) do
      {out, 0} ->
        out
        |> String.split()
        |> Enum.map(&String.to_integer/1)
        |> Enum.find(&qemu_process?/1)

      _ ->
        nil
    end
  end

  defp qemu_process?(pid) do
    case System.cmd("ps", ["-p", to_string(pid), "-o", "comm="], stderr_to_stdout: true) do
      {comm, 0} -> String.contains?(comm, "qemu-system-aarch64")
      _ -> false
    end
  end

  defp peer_bridge_binary do
    Application.load(:peer_bridge)
    path = Application.app_dir(:peer_bridge, ["priv", "peer_bridge"])

    File.exists?(path) ||
      raise "peer_bridge binary not found at #{path}; run `mix deps.compile peer_bridge`"

    path
  end

  defp setup_data_disk(nil, _work_dir), do: {nil, nil, []}

  defp setup_data_disk(spec, work_dir) do
    spec = Map.new(spec)
    size = Map.get(spec, :size, "256M")
    fault = Map.get(spec, :fault)
    path = Map.get(spec, :path) || create_data_disk(Path.join(work_dir, "data.img"), size)

    args =
      case fault do
        :blkdebug ->
          config = write_blkdebug_config(work_dir)

          # The `blkdebug:<config>:<image>` protocol filename reliably applies the
          # inject-error rules (the `-blockdev driver=blkdebug,config=` form did
          # not honor them here). Paths must be comma-free for -drive parsing.
          [
            "-drive",
            "if=none,file=blkdebug:#{config}:#{path},format=raw,id=vdata",
            "-device",
            "virtio-blk-device,drive=vdata"
          ]

        _ ->
          [
            "-drive",
            "if=none,file=#{path},format=raw,id=vdata",
            "-device",
            "virtio-blk-device,drive=vdata"
          ]
      end

    {path, fault, args}
  end

  defp create_primary_disk(fw_path, disk_path) do
    File.rm(disk_path)

    {_, 0} =
      System.cmd("fwup", ["-a", "-i", fw_path, "-d", disk_path, "-t", "complete"],
        stderr_to_stdout: true
      )

    disk_path
  end

  defp create_data_disk(path, size) do
    {_, 0} = System.cmd("qemu-img", ["create", "-f", "raw", path, size], stderr_to_stdout: true)
    path
  end

  defp write_blkdebug_config(work_dir) do
    config = Path.join(work_dir, "blkdebug.cfg")

    File.write!(config, """
    [inject-error]
    event = "read_aio"
    errno = "5"
    immediately = "on"
    once = "off"

    [inject-error]
    event = "write_aio"
    errno = "5"
    immediately = "on"
    once = "off"
    """)

    config
  end

  defp connect_qmp(qmp_port) do
    deadline = System.monotonic_time(:millisecond) + 10_000
    do_connect_qmp(qmp_port, deadline)
  end

  defp do_connect_qmp(qmp_port, deadline) do
    case QMP.connect(qmp_port) do
      {:ok, qmp} ->
        qmp

      {:error, reason} ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "could not connect to QMP on #{qmp_port}: #{inspect(reason)}"
        else
          Process.sleep(100)
          do_connect_qmp(qmp_port, deadline)
        end
    end
  end

  defp accel do
    case {os(), arch()} do
      {:macos, :aarch64} ->
        {"virt,accel=hvf", "host"}

      {:linux, :aarch64} ->
        if System.find_executable("kvm"), do: {"virt,accel=kvm", "host"}, else: {"virt", "cortex-a53"}

      _ ->
        {"virt", "cortex-a53"}
    end
  end

  defp os do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      _ -> :other
    end
  end

  defp arch do
    case to_string(:erlang.system_info(:system_architecture)) do
      "aarch64-" <> _ -> :aarch64
      _ -> :other
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp shell_join(args), do: Enum.map_join(args, " ", &shell_quote/1)

  defp shell_quote(arg) do
    "'" <> String.replace(to_string(arg), "'", "'\\''") <> "'"
  end

  defp safe(fun) do
    fun.()
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp token, do: :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

  defp raise_missing(env, key) do
    raise "missing #{env}; set the env var or pass #{inspect(key)} to VM.boot/1"
  end
end
