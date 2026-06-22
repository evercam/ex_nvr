defmodule ExNVR.QemuTest.Guest do
  @moduledoc """
  Helpers for inspecting and manipulating the guest over `:peer` RPC.
  """

  alias ExNVR.QemuTest.VM

  @doc """
  Return the mount point of the writable application data partition
  (`/dev/vda3`), raising with the current mount table if it is not mounted.
  """
  @spec app_mount(VM.t()) :: String.t()
  def app_mount(vm) do
    mounts = VM.call(vm, File, :read!, ["/proc/mounts"])

    entry =
      mounts
      |> String.split("\n", trim: true)
      |> Enum.find(fn line -> match?(["/dev/vda3" | _], String.split(line, " ")) end)

    case entry do
      nil -> raise "/dev/vda3 not mounted. Current mounts:\n#{mounts}"
      line -> line |> String.split(" ") |> Enum.at(1)
    end
  end

  @doc "True if `dir` in the guest is writable (a temp file can be created)."
  @spec writable?(VM.t(), String.t()) :: boolean()
  def writable?(vm, dir) do
    probe = Path.join(dir, "rt_write_probe")

    case VM.call(vm, File, :write, [probe, "ok"]) do
      :ok ->
        _ = VM.call(vm, File, :rm, [probe])
        true

      _ ->
        false
    end
  end

  @doc "Read a file in the guest, returning its contents or `nil` if absent."
  @spec read_file(VM.t(), String.t()) :: String.t() | nil
  def read_file(vm, path) do
    case VM.call(vm, File, :read, [path]) do
      {:ok, contents} -> contents
      {:error, _} -> nil
    end
  end

  @doc """
  Write `contents` to `path` in the guest, durably (O_SYNC), in one RPC. A raw fd
  can't be reused across `:peer.call`s - each runs in a different guest process.
  """
  @spec write_file(VM.t(), String.t(), String.t()) :: :ok
  def write_file(vm, path, contents) do
    :ok = VM.call(vm, :file, :write_file, [path, contents, [:sync]])
  end
end
