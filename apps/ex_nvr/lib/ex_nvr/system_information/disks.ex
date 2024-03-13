defmodule ExNVR.SystemInformation.Disks do
  @moduledoc """
  A module to get available disks on the machine using external utilities.

  Currently only `linux` machines are supported with the use of [lsblk](https://man7.org/linux/man-pages/man8/lsblk.8.html).
  """

  @manufacturers [
    {~r/WESTERN.*/, "Western Digital"},
    {~r/^WDC.*/, "Western Digital"},
    {~r/"WD.*/, "Western Digital"},
    {~r/"TOSHIBA./, "Toshiba"},
    {~r/"HITACHI./, "Hitachi"},
    {~r/^IC./, "Hitachi"},
    {~r/^HTS./, "Hitachi"},
    {~r/SANDISK./, "SanDisk"},
    {~r/KINGSTON./, "Kingston Technology"},
    {~r/^SONY./, "Sony"},
    {~r/TRANSCEND./, "Transcend"},
    {~r/SAMSUNG./, "Samsung"},
    {~r/^ST(?!I\\ )./, "Seagate"},
    {~r/^STI\\ ./, "SimpleTech"},
    {~r/^D...-./, "IBM"},
    {~r/^IBM./, "IBM"},
    {~r/^FUJITSU./, "Fujitsu"},
    {~r/^MP./, "Fujitsu"},
    {~r/^MK./, "Toshiba"},
    {~r/MAXTO./, "Maxtor"},
    {~r/PIONEER./, "Pioneer"},
    {~r/PHILIPS./, "Philips"},
    {~r/QUANTUM./, "Quantum Technology"},
    {~r/FIREBALL./, "Quantum Technology"},
    {~r/^VBOX./, "VirtualBox"},
    {~r/CORSAIR./, "Corsair Components"},
    {~r/CRUCIAL./, "Crucial"},
    {~r/ECM./, "ECM"},
    {~r/INTEL./, "INTEL"},
    {~r/EVO./, "Samsung"},
    {~r/APPLE./, "Apple"}
  ]

  require Logger

  alias ExNVR.SystemInformation.Disk

  alias ExNVR.Repo

  @spec create(map() | Disk.t()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    params
    |> Disk.changeset()
    |> Repo.insert()
  end

  def list() do
    Repo.all(Disk)
  end

  @spec list_available_disks(binary() | nil) :: [Disk.t()]
  def list_available_disks(mountpoint \\ nil) do
    case :os.type() do
      {:unix, :linux} ->
        list_linux_disks(mountpoint)

      _other ->
        []
    end
  end

  defp list_linux_disks(mountpoint) do
    with {:ok, data} <- run_lsblk_cmd(),
         {:ok, data} <- Jason.decode(data) do
      data
      |> Map.get("blockdevices", [])
      |> Enum.reject(&String.match?(&1["name"], ~r/^(loop|ram)/))
      |> maybe_filter_by_mountpoint(mountpoint)
      |> Enum.map(&map_linux_device_to_disk/1)
    else
      {:error, reason} = error ->
        Logger.error(inspect(reason))
        error
    end
  end

  defp run_lsblk_cmd() do
    case System.cmd("lsblk", ["-bJO"], env: [{"LC_ALL", "C"}], stderr_to_stdout: true) do
      {data, 0} ->
        {:ok, data}

      {error, exit_status} ->
        error_msg = """
        lsblk failed with status: #{exit_status}
        #{inspect(error)}
        """

        {:error, error_msg}
    end
  end

  defp maybe_filter_by_mountpoint(devices, nil), do: devices

  defp maybe_filter_by_mountpoint(devices, mountpoint) do
    Enum.filter(devices, fn device ->
      device["mountpoint"] == mountpoint or
        Enum.any?(device["children"] || [], &(&1["mountpoint"] == mountpoint))
    end)
  end

  defp map_linux_device_to_disk(device) do
    %{
      id: device["uuid"],
      vendor: get_vendor(device),
      model: device["model"],
      serial: device["serial"],
      size: device["size"],
      type: get_disk_type(device),
      transport: device["tran"],
      hotplug: device["hotplug"]
    }
  end

  defp get_vendor(device) do
    model = String.upcase("#{device["model"]}")
    default_value = String.trim("#{device["vendor"]}")

    Enum.find_value(@manufacturers, default_value, fn {pattern, manufacturer} ->
      if String.match?(model, pattern), do: manufacturer
    end)
  end

  defp get_disk_type(device) do
    cond do
      device["rota"] -> "HDD"
      device["tran"] == "nvme" -> "NVMe"
      true -> "SSD"
    end
  end
end
