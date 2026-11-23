defmodule ExNVR.Devices.Cameras.FirmwareTest do
  use ExUnit.Case, async: true

  import Mimic

  alias ExNVR.Devices.Cameras.Firmware
  alias ExNVR.RemoteConnection
  alias Plug.Conn

  @content "firmware content"
  @sha256 :crypto.hash(:sha256, @content) |> Base.encode16(case: :lower)

  setup_all do
    Mimic.copy(RemoteConnection)
  end

  describe "assigned/1" do
    test "returns the firmware assigned by the remote server" do
      expect(RemoteConnection, :push_and_wait, fn "camera-firmware", payload, _timeout ->
        assert payload == %{model: "SP111", platform: "52"}
        {:ok, %{"version" => "52.8.0.5", "url" => "https://fw/52", "sha256" => "ABC"}}
      end)

      assert {:ok, %Firmware{version: "52.8.0.5", url: "https://fw/52", sha256: "abc"}} =
               Firmware.assigned(%{model: "SP111", platform: "52"})
    end

    test "returns nil when no firmware is assigned" do
      expect(RemoteConnection, :push_and_wait, fn _event, _payload, _timeout -> {:ok, %{}} end)
      assert {:ok, nil} = Firmware.assigned(%{})
    end

    test "returns an error on invalid reply" do
      expect(RemoteConnection, :push_and_wait, fn _event, _payload, _timeout ->
        {:ok, %{"version" => "52.8.0.5"}}
      end)

      assert {:error, {:invalid_reply, %{"version" => "52.8.0.5"}}} = Firmware.assigned(%{})
    end

    test "returns remote server errors" do
      expect(RemoteConnection, :push_and_wait, fn _event, _payload, _timeout ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Firmware.assigned(%{})
    end
  end

  describe "download/2" do
    @describetag :tmp_dir

    setup do
      bypass = Bypass.open()

      firmware = %Firmware{
        version: "1.0",
        url: "http://localhost:#{bypass.port}/fw",
        sha256: @sha256
      }

      %{bypass: bypass, firmware: firmware}
    end

    test "downloads and verifies the firmware", %{
      bypass: bypass,
      firmware: firmware,
      tmp_dir: dir
    } do
      File.write!(Path.join(dir, "old_firmware"), "old")
      Bypass.expect_once(bypass, "GET", "/fw", &Conn.resp(&1, 200, @content))

      assert {:ok, path} = Firmware.download(firmware, dir)
      assert File.read!(path) == @content
      assert File.ls!(dir) == [@sha256]

      # reuse downloaded file
      assert {:ok, ^path} = Firmware.download(firmware, dir)
    end

    test "rejects corrupted files", %{bypass: bypass, firmware: firmware, tmp_dir: dir} do
      Bypass.expect_once(bypass, "GET", "/fw", &Conn.resp(&1, 200, "corrupted"))

      assert {:error, :checksum_mismatch} = Firmware.download(firmware, dir)
      assert File.ls!(dir) == []
    end

    test "returns download errors", %{bypass: bypass, firmware: firmware, tmp_dir: dir} do
      Bypass.expect_once(bypass, "GET", "/fw", &Conn.resp(&1, 403, "forbidden"))

      assert {:error, {:download_failed, 403}} = Firmware.download(firmware, dir)
      assert File.ls!(dir) == []
    end
  end
end
