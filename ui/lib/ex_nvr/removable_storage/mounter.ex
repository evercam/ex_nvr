defmodule ExNvr.RemovableStorage.Mounter do
  @moduledoc """
  Mounting usb/removable storage
  Creates a mountpoint -- a link  to usb
  """

  @poll_interval 3000
  @mount_points "./data/usb"

  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def mount(device) do
    GenServer.cast(__MODULE__, {:mount, device})
  end

  def init(_state) do
    listener()
    {:ok, %{removable_devices: %{} || ""}}
  end

  def handle_info(:listener, state) do
    r_devices =
      get_removable_storage()

    Phoenix.PubSub.broadcast(ExNVR.PubSub, "removable_storage_topic", {:usb, r_devices})

    listener()
    {:noreply, %{state | removable_devices: r_devices}}
  end

  def handle_cast({:mount, device}, state) do
    unless File.exists?(@mount_points),
      do: File.touch(@mount_points)

    {:noreply, state}
    # mount the device
  end

  def add_mountpoint(device) do
    {output, exit_code} =
      System.cmd("mount", ["/dev/#{device}", @mount_points])

    if exit_code != 0 do
      Logger.error("""
        Could not mount device to data/usb
      Error: #{output}
      """)
    end
  end

  def listener do
    Process.send_after(self(), :listener, @poll_interval)
  end

  @spec get_removable_storage() :: map()
  def get_removable_storage do
    {output, 0} = System.cmd("lsblk", ["-J"])

    details =
      Jason.decode!(output)["blockdevices"]
      |> Enum.filter(fn disk -> disk["rm"] == true end)
      |> Enum.map(fn disk ->
        %{
          name: disk["name"],
          size: disk["size"],
          partitions:
            Enum.map(disk["children"] || [], fn part ->
              if List.first(part["mountpoints"]) == nil do
                mount(part["name"])
              end

              %{
                name: part["name"],
                mountpoints: List.first(part["mountpoints"]),
                size: part["size"]
              }
            end)
        }
      end)
      |> List.first()

    details
  end
end
