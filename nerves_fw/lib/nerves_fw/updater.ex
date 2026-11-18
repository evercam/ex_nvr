defmodule ExNVR.Nerves.Updater do
  @moduledoc """
  Picks how each firmware update is downloaded.

  `NervesHubLink.UpdateManager.PartsUpdater` downloads the firmware in parts
  and checks each one against a checksum from NervesHub. An interrupted
  download resumes from the last good part instead of starting over, and a
  corrupted part is fetched again instead of failing later in `fwup`. That is
  what an NVR on a weak cellular link needs. The cost is that the whole
  firmware is kept in `/data` while it downloads, and stays there afterwards
  until the next firmware starts downloading.

  `NervesHubLink.UpdateManager.StreamingUpdater` writes the download straight
  into `fwup` and keeps nothing on disk, but starts over if the connection
  drops.

  So `PartsUpdater` is used when `/data` has room for the firmware plus some
  headroom left over for the database, logs and downloads, and
  `StreamingUpdater` otherwise. It is also used when NervesHub doesn't send the
  firmware's size, since then there is no telling whether it fits.

      config :nerves_hub_link, updater: ExNVR.Nerves.Updater

      config :ex_nvr_fw, ExNVR.Nerves.Updater, headroom_bytes: 268_435_456

  Free space is checked once, when the update starts. If something else fills
  `/data` during a long download, that attempt fails, and the next one checks
  again and streams.

  `NervesHubLink.UpdateManager` only ever calls `start_update/3` on the
  configured updater. Everything after that runs in the process of whichever
  updater this starts, so this module needs nothing else.
  """

  alias NervesHubLink.Message.UpdateInfo
  alias NervesHubLink.UpdateManager.{PartsUpdater, StreamingUpdater}

  require Logger

  # Has to match PartsUpdater's own default, since that is where it keeps parts.
  @default_cache_dir "/data/nerves_hub_link/firmware"
  @default_headroom_bytes 256 * 1024 * 1024
  @df_timeout 5_000

  @spec start_update(UpdateInfo.t(), NervesHubLink.FwupConfig.t(), [binary()]) ::
          GenServer.on_start()
  def start_update(%UpdateInfo{} = update_info, fwup_config, fwup_public_keys) do
    updater = choose(update_info)
    updater.start_update(update_info, fwup_config, fwup_public_keys)
  end

  @doc """
  The updater to use for this update: `PartsUpdater` when the firmware fits in
  the space left for it, `StreamingUpdater` when it doesn't or that can't be
  told.
  """
  @spec choose(UpdateInfo.t()) :: PartsUpdater | StreamingUpdater
  def choose(%UpdateInfo{size: size}) when is_integer(size) and size > 0 do
    cache_dir = cache_dir()
    # Parts already in the cache are as good as free: PartsUpdater either
    # reuses them, for the same firmware, or deletes them, for any other.
    room = available_bytes(cache_dir) + cached_bytes(cache_dir)
    needed = size + headroom_bytes()

    if room >= needed do
      Logger.info("[ExNVR.Nerves.Updater] Downloading in parts (#{room} bytes free)")
      PartsUpdater
    else
      stream(cache_dir, "#{needed} bytes needed, #{room} free")
    end
  end

  def choose(%UpdateInfo{}), do: stream(cache_dir(), "NervesHub didn't send the firmware size")

  defp stream(cache_dir, why) do
    Logger.warning(
      "[ExNVR.Nerves.Updater] Streaming the update instead of downloading in parts: #{why}"
    )

    # StreamingUpdater never touches the cache, so parts left by an earlier
    # attempt would otherwise go on holding the space that caused this.
    _ = File.rm_rf(cache_dir)

    StreamingUpdater
  end

  # This runs in NervesHubLink's UpdateManager, so it must not be able to hang
  # there. `df` gets a few seconds, and an answer that doesn't come back counts
  # as no space, which means streaming. `:disksup.get_disk_info/1` is avoided
  # for this reason: it is a call with no timeout into a process that may be
  # busy with its own periodic check.
  #
  # Monitored rather than linked, so not a Task: UpdateManager traps exits and
  # treats any :EXIT it doesn't recognise as the update failing, so a linked
  # process finishing normally would fail the update it was choosing for.
  defp available_bytes(path) do
    parent = self()
    ref = make_ref()

    {pid, monitor} =
      spawn_monitor(fn -> send(parent, {ref, df_available_bytes(existing_ancestor(path))}) end)

    receive do
      {^ref, bytes} ->
        Process.demonitor(monitor, [:flush])
        bytes

      {:DOWN, ^monitor, :process, ^pid, _reason} ->
        0
    after
      @df_timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])

        # It may have answered between the timeout and the kill.
        receive do
          {^ref, _bytes} -> :ok
        after
          0 -> :ok
        end

        0
    end
  end

  # POSIX output: a header, then
  # "<filesystem> <1024-blocks> <used> <available> <capacity> <mounted on>".
  defp df_available_bytes(path) do
    with {output, 0} <- System.cmd("df", ["-Pk", path], stderr_to_stdout: true),
         [_header, line | _rest] <- String.split(output, "\n", trim: true),
         [_filesystem, _blocks, _used, available | _rest] <- String.split(line),
         {kib, ""} <- Integer.parse(available) do
      kib * 1024
    else
      _unparseable -> 0
    end
  rescue
    # No df on the PATH.
    _error -> 0
  end

  # df only reports on a path that exists, and the cache directory doesn't
  # until PartsUpdater first runs.
  defp existing_ancestor(path) do
    parent = Path.dirname(path)

    cond do
      File.dir?(path) -> path
      parent == path -> path
      true -> existing_ancestor(parent)
    end
  end

  defp cached_bytes(cache_dir) do
    cache_dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.reduce(0, fn path, total ->
      case File.lstat(path) do
        {:ok, %File.Stat{type: :regular, size: size}} -> total + size
        _other -> total
      end
    end)
  end

  defp cache_dir do
    :nerves_hub_link
    |> Application.get_env(PartsUpdater, [])
    |> Keyword.get(:cache_dir, @default_cache_dir)
  end

  defp headroom_bytes do
    :ex_nvr_fw
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:headroom_bytes, @default_headroom_bytes)
  end
end
