defmodule ExNVR.QemuTest.Faults do
  @moduledoc """
  High-level fault-injection API built on the QMP control plane and host-side
  image manipulation. Everything here is "Layer 1": injected from *outside* the
  guest, so it works regardless of the guest kernel and the same way on macOS and
  Linux hosts.

  Guest-side faults that need extra kernel features (packet loss/reorder via
  `netem`, rate-based block failures via the fault-injection framework,
  device-mapper flakey/delay/dust) are out of scope here and not implemented yet.
  """

  alias ExNVR.QemuTest.VM

  @sector 512
  @mbr_first_entry 446
  @entry_size 16

  @doc """
  Throttle a block device's I/O (latency / bandwidth). Defaults to the secondary
  data disk (`"vdata"`). Pass any of `:iops`, `:bps`, `:iops_rd`, `:iops_wr`,
  `:bps_rd`, `:bps_wr` (per second; `0` means unlimited).

      Faults.disk_throttle(vm, bps_rd: 1_048_576)   # read at 1 MB/s
  """
  @spec disk_throttle(VM.t(), keyword()) :: term()
  def disk_throttle(vm, opts) do
    device = Keyword.get(opts, :device, "vdata")

    args = %{
      device: device,
      bps: Keyword.get(opts, :bps, 0),
      bps_rd: Keyword.get(opts, :bps_rd, 0),
      bps_wr: Keyword.get(opts, :bps_wr, 0),
      iops: Keyword.get(opts, :iops, 0),
      iops_rd: Keyword.get(opts, :iops_rd, 0),
      iops_wr: Keyword.get(opts, :iops_wr, 0)
    }

    VM.qmp!(vm, "block_set_io_throttle", args)
  end

  @doc "Remove all throttling from a device (default `\"vdata\"`)."
  @spec disk_unthrottle(VM.t(), String.t()) :: term()
  def disk_unthrottle(vm, device \\ "vdata") do
    disk_throttle(vm, device: device)
  end

  @doc """
  Add network latency by inserting a `filter-buffer` on the `eth0` netdev. The
  filter holds packets and releases them every `interval`, adding up to
  `latency_ms` of delay. Remove it with `net_clear/1`.
  """
  @spec net_latency(VM.t(), pos_integer()) :: term()
  def net_latency(vm, latency_ms) do
    VM.qmp!(vm, "object-add", %{
      "qom-type" => "filter-buffer",
      "id" => "fb0",
      "netdev" => "eth0",
      "interval" => latency_ms * 1000
    })
  end

  @doc "Remove the network latency filter added by `net_latency/2`."
  @spec net_clear(VM.t()) :: term()
  def net_clear(vm) do
    VM.qmp!(vm, "object-del", %{"id" => "fb0"})
  end

  @doc """
  Corrupt a partition in a disk image on the host (the VM must be stopped).

  Parses the MBR to find the partition's start sector and overwrites the first
  `bytes` (default 1 MiB, enough to clobber the filesystem superblock) with
  `0xFF`. Partition index `2` is the writable application data partition.
  """
  @spec corrupt_partition(String.t(), non_neg_integer(), pos_integer()) :: :ok
  def corrupt_partition(image_path, index \\ 2, bytes \\ 1_048_576) do
    {:ok, file} = :file.open(image_path, [:read, :write, :binary, :raw])

    try do
      {:ok, mbr} = :file.pread(file, 0, 512)
      start_sector = partition_start_sector(mbr, index)

      if start_sector == 0 do
        raise "partition #{index} not found in MBR of #{image_path}"
      end

      offset = start_sector * @sector
      :ok = :file.pwrite(file, offset, :binary.copy(<<0xFF>>, bytes))
    after
      :file.close(file)
    end

    :ok
  end

  @doc """
  Return `{start_sector, sector_count}` for an MBR partition in a disk image.
  Useful for inspection in tests.
  """
  @spec partition_info(String.t(), non_neg_integer()) :: {non_neg_integer(), non_neg_integer()}
  def partition_info(image_path, index) do
    {:ok, file} = :file.open(image_path, [:read, :binary, :raw])

    try do
      {:ok, mbr} = :file.pread(file, 0, 512)
      entry = :binary.part(mbr, @mbr_first_entry + index * @entry_size, @entry_size)
      <<_status::8, _chs_first::24, _type::8, _chs_last::24, lba::little-32, count::little-32>> = entry
      {lba, count}
    after
      :file.close(file)
    end
  end

  defp partition_start_sector(mbr, index) do
    entry = :binary.part(mbr, @mbr_first_entry + index * @entry_size, @entry_size)
    <<_::binary-size(8), lba::little-32, _count::little-32>> = entry
    lba
  end
end
