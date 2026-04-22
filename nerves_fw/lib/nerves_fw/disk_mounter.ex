defmodule ExNVR.Nerves.DiskMounter do
  @moduledoc """
  Module responsible for mounting hard drives on `fstab` file.
  """
  require Logger

  use GenServer

  @usb_mountpoint "/data/usb"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_fstab_entry(uuid, mountpoint, fstype) do
    GenServer.call(__MODULE__, {:add_fstab_entry, {uuid, mountpoint, fstype}})
  end

  def list_fstab_entries do
    GenServer.call(__MODULE__, :list_fstab_entries)
  end

  def delete_fstab_entries(options) do
    GenServer.call(__MODULE__, {:delete_fstab_entries, options})
  end

  def mount do
    GenServer.call(__MODULE__, :mount)
  end

  def mount_usb do
    GenServer.call(__MODULE__, :usb_mount)
  end

  def umount(lazy? \\ true) do
    GenServer.call(__MODULE__, {:umount, lazy?})
  end

  @impl true
  def init(opts) do
    NervesUEvent.subscribe([])

    fstab = Keyword.get(opts, :fstab, "/data/fstab")

    unless File.exists?(fstab), do: File.touch(fstab)

    {:ok, %{fstab: fstab, devname: []}, {:continue, :mount}}
  end

  @impl true
  def handle_continue(:mount, state) do
    mount_all(state)
    {:noreply, state}
  end

  @impl true
  def handle_call({:add_fstab_entry, {uuid, mountpoint, fstype}}, _from, state) do
    entry = "UUID=\"#{uuid}\" #{mountpoint} #{fstype} defaults 0 1\n"
    res = File.write(state.fstab, entry, [:append])
    mount_all(state)

    {:reply, res, state}
  end

  @impl true
  def handle_call(:list_fstab_entries, _from, state) do
    {:reply, File.read!(state.fstab), state}
  end

  @impl true
  def handle_call({:delete_fstab_entries, options}, _from, state) do
    uuid = options[:uuid] || ""
    mountpoint = options[:mountpoint] || ""

    File.read!(state.fstab)
    |> String.split("\n")
    |> Enum.reject(fn line ->
      (uuid != "" and String.starts_with?(line, "UUID=\"#{uuid}\"")) or
        (mountpoint != "" and String.contains?(line, mountpoint))
    end)
    |> Enum.join("\n")
    |> then(&File.write!(state.fstab, &1))

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:mount, _from, state) do
    mount_all(state)
    {:reply, :ok, state}
  end

  def handle_call(:usb_mount, _from, state) do
    Logger.info("Mounting USB devices: #{inspect(state)}")

    exit_code =
      state.devname
      |> Enum.map(fn dev ->
        {block_info, 0} =
          System.cmd("lsblk", ["-J", "-o", "NAME,SIZE,TYPE,MOUNTPOINT,LABEL", "/dev/#{dev}"])

        Jason.decode!(block_info)["blockdevices"]
        |> List.first()
        |> mount_usb_partition(state)
      end)

    if exit_code != 0 do
      Logger.error("""
      Could not mount from fstab
      Error: #{state.devname}
      """)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:umount, lazy?}, _from, state) do
    Logger.info("[DiskMounter] unmouting all filesystems declared in fstab")
    args = if lazy?, do: ["-l"], else: []

    File.read!(state.fstab)
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&Enum.at(String.split(&1, " "), 1))
    |> Enum.each(&System.cmd("umount", args ++ [&1]))

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(
        %PropertyTable.Event{value: %{"subsystem" => "block", "devtype" => "disk"}} = event,
        state
      ) do
    mount_all(state)

    state =
      %{
        (state || %{devname: []})
        | devname: (state.devname ++ [event.value["devname"]]) |> Enum.uniq()
      }

    Phoenix.PubSub.broadcast(
      ExNVR.PubSub,
      "removable_device_detected",
      :removable_device_detected
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(
        %PropertyTable.Event{
          value: nil,
          previous_value: %{"subsystem" => "block", "devtype" => "disk"}
        } = event,
        state
      ) do
    Logger.warning("[Remove] Block kernel event: #{inspect(event.previous_value)}")
    ExNVR.Events.create_event(%{type: "disk", metadata: %{connected: 0}})
    {:noreply, state}
  end

  @impl true
  def handle_info(_event, state) do
    {:noreply, state}
  end

  defp mount_all(state) do
    {output, exit_code} = System.cmd("mount", ["-T", state.fstab, "-a"], stderr_to_stdout: true)

    if exit_code != 0 do
      Logger.error("""
      Could not mount from fstab
      Error: #{output}
      """)
    end
  end

  defp mount_usb_partition(block_info, state) do
    block_info["children"]
    |> Enum.map(fn partition ->
      if partition["mountpoint"] == nil do
        mountpoint = @usb_mountpoint <> "/#{partition["label"] || partition["name"]}"

        File.mkdir_p!(mountpoint)

        {output, exit_code} =
          System.cmd("mount", ["/dev/#{partition["name"]}", mountpoint], stderr_to_stdout: true)

        exit_code
      end
    end)
  end
end
