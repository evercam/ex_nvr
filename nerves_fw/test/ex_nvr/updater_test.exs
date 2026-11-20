defmodule ExNVR.Nerves.UpdaterTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import Mimic

  alias ExNVR.Nerves.Updater
  alias NervesHubLink.Message.UpdateInfo
  alias NervesHubLink.UpdateManager.{PartsUpdater, StreamingUpdater}

  @moduletag :tmp_dir
  @moduletag capture_log: true

  setup :verify_on_exit!

  setup_all do
    Mimic.copy(PartsUpdater)
    Mimic.copy(StreamingUpdater)
    :ok
  end

  setup %{tmp_dir: tmp_dir} do
    cache_dir = Path.join(tmp_dir, "firmware")

    Application.put_env(:nerves_hub_link, PartsUpdater, cache_dir: cache_dir)

    on_exit(fn ->
      Application.delete_env(:nerves_hub_link, PartsUpdater)
      Application.delete_env(:ex_nvr_fw, Updater)
    end)

    %{cache_dir: cache_dir}
  end

  defp update_info(size),
    do: %UpdateInfo{firmware_url: URI.new!("https://example.com/fw"), size: size}

  defp headroom(bytes), do: Application.put_env(:ex_nvr_fw, Updater, headroom_bytes: bytes)

  describe "choose/1" do
    test "downloads in parts when the firmware fits" do
      headroom(0)
      assert Updater.choose(update_info(70_000_000)) == PartsUpdater
    end

    test "streams when the firmware and headroom don't fit, and clears old parts",
         %{cache_dir: cache_dir} do
      File.mkdir_p!(Path.join(cache_dir, "old-firmware"))
      File.write!(Path.join([cache_dir, "old-firmware", "part-0"]), "part")

      # More than any test machine has free.
      headroom(1024 ** 6)

      assert Updater.choose(update_info(70_000_000)) == StreamingUpdater
      refute File.exists?(cache_dir)
    end

    test "counts parts already in the cache as free space", %{cache_dir: cache_dir} do
      cached = 16 * 1024 * 1024
      File.mkdir_p!(cache_dir)
      File.write!(Path.join(cache_dir, "part-0"), :binary.copy(<<0>>, cached))

      free = free_bytes(cache_dir)

      # Fits only if the cached part counts towards the room. Half of it is
      # left as slack for whatever else is writing to this disk meanwhile.
      headroom(free + div(cached, 2) - 1)

      assert Updater.choose(update_info(1)) == PartsUpdater
    end

    test "leaves no :EXIT message for a caller that traps exits" do
      # NervesHubLink's UpdateManager traps exits and fails the running update
      # on any :EXIT it doesn't recognise.
      Process.flag(:trap_exit, true)
      headroom(0)

      assert Updater.choose(update_info(70_000_000)) == PartsUpdater
      refute_receive {:EXIT, _pid, _reason}, 100
    end

    test "streams when NervesHub doesn't send the firmware size" do
      headroom(0)
      assert Updater.choose(update_info(nil)) == StreamingUpdater
    end
  end

  describe "start_update/3" do
    test "starts the chosen updater with the same arguments" do
      headroom(0)
      info = update_info(70_000_000)
      pid = self()

      expect(PartsUpdater, :start_update, fn ^info, :fwup_config, ["key"] -> {:ok, pid} end)
      reject(&StreamingUpdater.start_update/3)

      assert Updater.start_update(info, :fwup_config, ["key"]) == {:ok, pid}
    end
  end

  defp free_bytes(path) do
    {output, 0} = System.cmd("df", ["-Pk", path])
    [_header, line | _rest] = String.split(output, "\n", trim: true)
    [_filesystem, _blocks, _used, available | _rest] = String.split(line)
    String.to_integer(available) * 1024
  end
end
