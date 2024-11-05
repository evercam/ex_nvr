defmodule ExNVR.Disk do
  @moduledoc """
  Get disk information
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

  defmodule FS do
    @moduledoc """
    A struct representing a filesystem
    """

    @type t :: %__MODULE__{}

    @derive Jason.Encoder
    defstruct [:type, :size, :avail, :uuid, :read_only, :mountpoint]
  end

  defmodule Part do
    @moduledoc """
    A struct representing a partition
    """

    @type t :: %__MODULE__{}

    @derive Jason.Encoder
    defstruct [:name, :path, :fs]
  end

  @type t :: %__MODULE__{}

  @derive Jason.Encoder
  defstruct [:name, :vendor, :model, :serial, :path, :size, :fs, :hotplug, :tran, :parts]

  @doc """
  List available hard drives
  """
  @spec list_drives() :: [t()]
  def list_drives() do
    case :os.type() do
      {:unix, _} ->
        list_unix_drives()

      other ->
        raise "list hard drives for os: #{inspect(other)} is not supported"
    end
  end

  @spec has_filesystem?(t() | Part.t()) :: boolean()
  def has_filesystem?(%__MODULE__{} = disk) do
    not is_nil(disk.fs) or Enum.any?(disk.parts, &has_filesystem?/1)
  end

  def has_filesystem?(%Part{} = part), do: not is_nil(part.fs)

  defp list_unix_drives() do
    # include only disks with major version of 8 and 259
    cmd =
      System.cmd(
        "lsblk",
        [
          "-I",
          "8,259",
          "-Jbo",
          "NAME,PATH,VENDOR,MODEL,SERIAL,SIZE,HOTPLUG,TRAN,FSTYPE,FSSIZE,FSAVAIL,UUID,RO,MOUNTPOINT"
        ],
        stderr_to_stdout: true
      )

    case cmd do
      {output, 0} ->
        {:ok, output |> Jason.decode!() |> map()}

      {output, _} ->
        {:error, output}
    end
  end

  defp map(%{"blockdevices" => devices}) do
    Enum.map(devices, fn device ->
      %__MODULE__{
        name: device["name"],
        path: device["path"],
        vendor: get_vendor(device["vendor"], device["model"]),
        model: device["model"],
        serial: device["serial"],
        size: device["size"],
        hotplug: device["hotplug"],
        tran: device["tran"],
        parts: Enum.map(device["children"] || [], &map_part/1),
        fs: map_fs(device)
      }
    end)
  end

  defp map_part(part) do
    %Part{
      name: part["name"],
      path: part["path"],
      fs: map_fs(part)
    }
  end

  defp map_fs(%{"fstype" => nil}), do: nil

  defp map_fs(device_or_part) do
    %FS{
      type: device_or_part["fstype"],
      size: device_or_part["fssize"],
      avail: device_or_part["fsavail"],
      uuid: device_or_part["uuid"],
      read_only: device_or_part["ro"],
      mountpoint: device_or_part["mountpoint"]
    }
  end

  defp get_vendor(vendor, model) do
    model = to_string(model) |> String.upcase()
    default_value = to_string(vendor) |> String.trim()

    Enum.find_value(@manufacturers, default_value, fn {pattern, manufacturer} ->
      if String.match?(model, pattern), do: manufacturer
    end)
  end
end
