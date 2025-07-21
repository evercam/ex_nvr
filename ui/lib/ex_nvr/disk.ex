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

  @type list_opts :: [major_number: [integer()]]

  @derive Jason.Encoder
  defstruct [
    :name,
    :vendor,
    :model,
    :serial,
    :path,
    :size,
    :fs,
    :hotplug,
    :tran,
    :parts,
    :form_factor,
    :type
  ]

  @doc """
  List available hard drives.

  The following options may be provided:
    * `major_number` - Get only drives with this major number. Default is `[8, 259]`.
  """
  @spec list_drives(list_opts()) :: {:ok, [t()]} | {:error, any()}
  def list_drives(opts \\ []) do
    case :os.type() do
      {:unix, :darwin} -> {:error, :not_supported}
      {:unix, _} -> list_unix_drives(opts)
      _other -> {:error, :not_supported}
    end
  end

  @spec list_drives!(list_opts()) :: [t()]
  def list_drives!(opts \\ []) do
    case list_drives(opts) do
      {:ok, drives} -> drives
      {:error, reason} -> raise "cannot list hard drives due to: #{inspect(reason)}"
    end
  end

  @spec has_filesystem?(t() | Part.t()) :: boolean()
  def has_filesystem?(%__MODULE__{} = disk) do
    not is_nil(disk.fs) or Enum.any?(disk.parts, &has_filesystem?/1)
  end

  def has_filesystem?(%Part{} = part), do: not is_nil(part.fs)

  defp list_unix_drives(opts) do
    # By default retrieve disks with major version of 8 and 259
    major_numbers = Keyword.get(opts, :major_number, [8, 259])

    cmd =
      System.cmd(
        "lsblk",
        [
          "-I",
          Enum.join(major_numbers, ","),
          "-Jbo",
          "NAME,PATH,VENDOR,MODEL,SERIAL,SIZE,HOTPLUG,TRAN,FSTYPE,FSSIZE,FSAVAIL,UUID,RO,MOUNTPOINT"
        ],
        stderr_to_stdout: true
      )

    case cmd do
      {output, 0} ->
        {:ok, output |> JSON.decode!() |> map()}

      {output, _} ->
        {:error, output}
    end
  end

  defp map(%{"blockdevices" => devices}) do
    Enum.map(devices, fn device ->
      disk_info = smartctl_get_disk_info(device["path"])
      model = disk_info["model_name"] || String.trim(to_string(device["model"]))

      disk = %__MODULE__{
        name: device["name"],
        path: device["path"],
        vendor: get_vendor(device["vendor"], model),
        model: model,
        serial: disk_info["serial_number"] || String.trim(to_string(device["serial"])),
        size: device["size"],
        hotplug: device["hotplug"],
        tran: device["tran"],
        parts: Enum.map(device["children"] || [], &map_part/1),
        fs: map_fs(device),
        form_factor: get_in(disk_info, ["form_factor", "name"])
      }

      guess_storage_type(disk, disk_info)
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
      size: device_or_part["fssize"] |> to_integer(),
      avail: device_or_part["fsavail"] |> to_integer(),
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

  # get disk info using smartctl if available
  defp smartctl_get_disk_info(drive) do
    if path = System.find_executable("smartctl") do
      opts = [stderr_to_stdout: true]
      args = ["-ji", drive]

      with {_error, exit_code} when exit_code != 0 <- System.cmd(path, args, opts),
           {_error, exit_code} when exit_code != 0 <- System.cmd(path, ["-d", "sat" | args], opts) do
        %{}
      else
        {output, 0} ->
          JSON.decode!(output)
      end
    else
      %{}
    end
  end

  defp guess_storage_type(disk, smart_info) do
    path = "/sys/block/#{disk.name}/queue/rotational"
    rotation_rate = Map.get(smart_info, "rotation_rate")

    type =
      cond do
        disk.tran == "nvme" -> :nvme
        File.exists?(path) and String.trim(File.read!(path)) == "1" -> :hdd
        rotation_rate != nil and rotation_rate != 0 -> :hdd
        rotation_rate == 0 -> :ssd
        true -> nil
      end

    %{disk | type: type}
  end

  defp to_integer(nil), do: nil
  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value), do: String.to_integer(value)
end
