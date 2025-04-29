defmodule ExNVR.Nerves.DiskMounter do
  @moduledoc """
  Module responsible for mounting hard drives on `fstab` file.
  """
  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_fstab_entry(uuid, mountpoint, fstype) do
    GenServer.call(__MODULE__, {:add_fstab_entry, {uuid, mountpoint, fstype}})
  end

  def list_fstab_entries() do
    GenServer.call(__MODULE__, :list_fstab_entries)
  end

  def delete_fstab_entries(options) do
    GenServer.call(__MODULE__, {:delete_fstab_entries, options})
  end

  @impl true
  def init(opts) do
    NervesUEvent.subscribe([])

    fstab = Keyword.get(opts, :fstab, "/data/fstab")
    unless File.exists?(fstab), do: File.touch(fstab)

    {:ok, %{fstab: fstab}, {:continue, :mount}}
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
  def handle_info(%PropertyTable.Event{value: %{"subsystem" => "block"}} = event, state) do
    Logger.warning("New block device connected: #{inspect(event.value)}")
    mount_all(state)
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
end
