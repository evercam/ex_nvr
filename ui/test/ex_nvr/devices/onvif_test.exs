defmodule ExNVR.Devices.OnvifTest do
  use ExUnit.Case, async: true

  import Mimic

  alias ExNVR.Devices.Cameras.{
    DateTimeSettings,
    Firmware,
    ImageSettings,
    RecordingSettings,
    Timezones
  }

  alias ExNVR.Devices.Cameras.HttpClient.Milesight
  alias ExNVR.Devices.Onvif
  alias ExNVR.Devices.Onvif.AutoConfig

  @device %ExOnvif.Device{manufacturer: "HIKVISION"}

  setup_all do
    Mimic.copy(ExOnvif.Devices)
    Mimic.copy(ExOnvif.Media2)
    Mimic.copy(Milesight)
    Mimic.copy(Firmware)
  end

  setup do
    stub(ExOnvif.Media2, :get_profiles, fn _device -> {:error, :unavailable} end)
    stub(Milesight, :sd_card_status, fn _url, _opts -> {:ok, :ready} end)
    stub(Milesight, :set_recording_settings, fn _url, _settings, _opts -> :ok end)
    :ok
  end

  describe "auto_configure/2 date & time" do
    test "set NTP server and timezone before anything else" do
      test_pid = self()

      stub(ExOnvif.Media2, :get_profiles, fn _device ->
        send(test_pid, :profiles)
        {:error, :unavailable}
      end)

      expect(ExOnvif.Devices, :set_ntp, fn _device, ntp ->
        assert %{from_dhcp: false, ntp_manual: %{type: :dns, dns_name: "time1.google.com"}} = ntp
        send(test_pid, :ntp)
        :ok
      end)

      expect(ExOnvif.Devices, :set_system_date_and_time, fn _device, date_time ->
        assert %{date_time_type: :ntp, daylight_savings: true} = date_time
        assert date_time.time_zone.tz == "GMT0IST,M3.5.0/1,M10.5.0"
        :ok
      end)

      assert %AutoConfig{date_time: :ok, main_stream: {:error, :unavailable}} =
               Onvif.auto_configure(@device, timezone: "Europe/Dublin")

      assert {:messages, [:ntp, :profiles]} = Process.info(self(), :messages)
    end

    test "skipped when no timezone is provided" do
      reject(ExOnvif.Devices, :set_ntp, 2)
      assert %AutoConfig{date_time: nil} = Onvif.auto_configure(@device)
    end

    test "unknown timezone" do
      reject(ExOnvif.Devices, :set_ntp, 2)

      assert %AutoConfig{date_time: {:error, {:unknown_timezone, "Mars/Olympus"}}} =
               Onvif.auto_configure(@device, timezone: "Mars/Olympus")
    end

    test "camera error" do
      expect(ExOnvif.Devices, :set_ntp, fn _device, _ntp -> {:error, :timeout} end)
      reject(ExOnvif.Devices, :set_system_date_and_time, 2)

      assert %AutoConfig{date_time: {:error, :timeout}} =
               Onvif.auto_configure(@device, timezone: "Europe/Dublin")
    end
  end

  describe "auto_configure/2 Milesight OSD" do
    setup do
      stub(Milesight, :set_date_time, fn _url, _settings, _opts -> :ok end)
      stub(Milesight, :set_image_settings, fn _url, _settings, _opts -> :ok end)

      %{device: %ExOnvif.Device{manufacturer: "Milesight Technology Co.,Ltd."}}
    end

    for {timezone, date_format} <- [
          {"America/Chicago", :mdy},
          {"US/Pacific", :mdy},
          {"Pacific/Honolulu", :mdy},
          {"America/Toronto", :dmy},
          {"Europe/Dublin", :dmy},
          {nil, :dmy}
        ] do
      test "use #{date_format} date format for #{inspect(timezone)} timezone", %{device: device} do
        expect(Milesight, :set_osd, fn _url, osd, _opts ->
          assert osd.date_format == unquote(date_format)
          :ok
        end)

        assert %{osd: :ok} = Onvif.auto_configure(device, timezone: unquote(timezone))
      end
    end
  end

  test "auto_configure/2 uses Milesight API to configure date & time" do
    device = %ExOnvif.Device{manufacturer: "Milesight Technology Co.,Ltd."}

    reject(ExOnvif.Devices, :set_ntp, 2)
    stub(Milesight, :set_image_settings, fn _url, _settings, _opts -> :ok end)
    stub(Milesight, :set_osd, fn _url, _osd, _opts -> :ok end)

    expect(Milesight, :set_date_time, fn _url, settings, _opts ->
      assert %DateTimeSettings{timezone: "US/Central", ntp_server: "time1.google.com"} = settings
      :ok
    end)

    assert %AutoConfig{date_time: :ok} = Onvif.auto_configure(device, timezone: "US/Central")
  end

  describe "auto_configure/2 Milesight SD card" do
    setup do
      stub(Milesight, :set_date_time, fn _url, _settings, _opts -> :ok end)
      stub(Milesight, :set_image_settings, fn _url, _settings, _opts -> :ok end)
      stub(Milesight, :set_osd, fn _url, _osd, _opts -> :ok end)

      %{device: %ExOnvif.Device{manufacturer: "Milesight Technology Co.,Ltd."}}
    end

    test "format unformatted card and record 24/7", %{device: device} do
      expect(Milesight, :sd_card_status, fn _url, _opts -> {:ok, :unformatted} end)
      expect(Milesight, :format_sd_card, fn _url, _opts -> :ok end)

      expect(Milesight, :set_recording_settings, fn _url, settings, _opts ->
        assert %RecordingSettings{stream: :main, schedule: :always, overwrite: true} = settings
        :ok
      end)

      assert %AutoConfig{sd_card: :ok, sd_recording: :ok} = Onvif.auto_configure(device)
    end

    test "do not format a formatted card", %{device: device} do
      reject(Milesight, :format_sd_card, 2)
      assert %AutoConfig{sd_card: :ok, sd_recording: :ok} = Onvif.auto_configure(device)
    end

    test "no SD card", %{device: device} do
      expect(Milesight, :sd_card_status, fn _url, _opts -> {:ok, :not_inserted} end)
      reject(Milesight, :format_sd_card, 2)
      reject(Milesight, :set_recording_settings, 3)

      assert %AutoConfig{sd_card: {:error, :no_sd_card}, sd_recording: nil} =
               Onvif.auto_configure(device)
    end

    test "bad SD card", %{device: device} do
      expect(Milesight, :sd_card_status, fn _url, _opts -> {:ok, :bad} end)
      reject(Milesight, :set_recording_settings, 3)

      assert %AutoConfig{sd_card: {:error, {:sd_card, :bad}}, sd_recording: nil} =
               Onvif.auto_configure(device)
    end

    test "format error", %{device: device} do
      expect(Milesight, :sd_card_status, fn _url, _opts -> {:ok, :unformatted} end)
      expect(Milesight, :format_sd_card, fn _url, _opts -> {:error, {500, "boom"}} end)
      reject(Milesight, :set_recording_settings, 3)

      assert %AutoConfig{sd_card: {:error, {500, "boom"}}, sd_recording: nil} =
               Onvif.auto_configure(device)
    end
  end

  describe "auto_configure/2 steps" do
    setup do
      %{device: %ExOnvif.Device{manufacturer: "Milesight Technology Co.,Ltd."}}
    end

    test "supported steps", %{device: device} do
      assert Onvif.auto_config_steps(device) == [
               :date_time,
               :streams,
               :image_settings,
               :osd,
               :sd_card
             ]

      assert Onvif.auto_config_steps(@device) == [:date_time, :streams]

      assert Onvif.auto_config_steps(%ExOnvif.Device{manufacturer: "AXIS"}) == [
               :date_time,
               :streams
             ]
    end

    test "run only the selected steps", %{device: device} do
      reject(Milesight, :set_date_time, 3)
      reject(ExOnvif.Media2, :get_profiles, 1)
      reject(Milesight, :set_image_settings, 3)
      reject(Milesight, :sd_card_status, 2)
      reject(Milesight, :set_recording_settings, 3)
      expect(Milesight, :set_osd, fn _url, _osd, _opts -> :ok end)

      assert Onvif.auto_configure(device, timezone: "Europe/Dublin", steps: [:osd]) ==
               %AutoConfig{osd: :ok}
    end

    test "skip SD card recording", %{device: device} do
      stub(Milesight, :set_date_time, fn _url, _settings, _opts -> :ok end)
      stub(Milesight, :set_image_settings, fn _url, _settings, _opts -> :ok end)
      stub(Milesight, :set_osd, fn _url, _osd, _opts -> :ok end)
      reject(Milesight, :sd_card_status, 2)
      reject(Milesight, :set_recording_settings, 3)

      assert %AutoConfig{date_time: :ok, osd: :ok, sd_card: nil, sd_recording: nil} =
               Onvif.auto_configure(device,
                 timezone: "Europe/Dublin",
                 steps: [:date_time, :streams, :image_settings, :osd]
               )
    end

    test "enable lens distortion correction with image settings", %{device: device} do
      expect(Milesight, :set_image_settings, fn _url, settings, _opts ->
        assert %ImageSettings{
                 brightness: 50,
                 contrast: 65,
                 saturation: 60,
                 ldc: true
               } = settings

        :ok
      end)

      assert %AutoConfig{image_settings: :ok} =
               Onvif.auto_configure(device, steps: [:image_settings])
    end

    test "skip streams on other vendors" do
      reject(ExOnvif.Media2, :get_profiles, 1)
      assert Onvif.auto_configure(@device, steps: []) == %AutoConfig{}
    end
  end

  describe "firmware" do
    @firmware %Firmware{version: "52.8.0.5", url: "https://fw/52", sha256: "abc"}
    @info %{platform: "52", version: "52.8.0.4", model: "SP111"}

    setup do
      stub(Firmware, :available?, fn -> true end)
      stub(Milesight, :firmware_info, fn _url, _opts -> {:ok, @info} end)

      device = %ExOnvif.Device{
        manufacturer: "Milesight Technology Co.,Ltd.",
        address: "http://camera",
        serial_number: "6CF17E000001"
      }

      %{device: device}
    end

    test "is only offered with a remote connection", %{device: device} do
      assert :firmware in Onvif.auto_config_steps(device)
      refute :firmware in Onvif.auto_config_steps(@device)

      stub(Firmware, :available?, fn -> false end)
      refute :firmware in Onvif.auto_config_steps(device)
    end

    test "upgrade when the assigned firmware differs", %{device: device} do
      expect(Firmware, :assigned, fn request ->
        assert request == %{
                 vendor: "Milesight Technology Co.,Ltd.",
                 model: "SP111",
                 platform: "52",
                 version: "52.8.0.4",
                 serial: "6CF17E000001"
               }

        {:ok, @firmware}
      end)

      assert %AutoConfig{firmware: {:upgrade, "52.8.0.4", @firmware}} =
               Onvif.auto_configure(device, steps: [:firmware])
    end

    test "up to date", %{device: device} do
      stub(Firmware, :assigned, fn _request -> {:ok, %{@firmware | version: "52.8.0.4"}} end)
      assert %AutoConfig{firmware: :ok} = Onvif.auto_configure(device, steps: [:firmware])

      stub(Firmware, :assigned, fn _request -> {:ok, nil} end)
      assert %AutoConfig{firmware: :ok} = Onvif.auto_configure(device, steps: [:firmware])
    end

    test "check errors", %{device: device} do
      stub(Firmware, :assigned, fn _request -> {:error, :timeout} end)

      assert %AutoConfig{firmware: {:error, :timeout}} =
               Onvif.auto_configure(device, steps: [:firmware])
    end

    test "upgrade_firmware/4 uploads and waits for the new version", %{device: device} do
      expect(Firmware, :download, fn @firmware -> {:ok, "/tmp/fw"} end)

      expect(Milesight, :upgrade_firmware, fn "http://camera", "/tmp/fw", _opts ->
        {:error, %Req.TransportError{reason: :closed}}
      end)

      Milesight
      |> expect(:firmware_info, fn _url, _opts -> {:error, :econnrefused} end)
      |> expect(:firmware_info, fn _url, _opts -> {:ok, %{@info | version: "52.8.0.5"}} end)

      test_pid = self()
      notify = &send(test_pid, {:progress, &1})

      assert :ok = Onvif.upgrade_firmware(device, @firmware, notify, poll_interval: 0)

      assert_received {:progress, :downloading}
      assert_received {:progress, :uploading}
      assert_received {:progress, :rebooting}
      assert_received {:progress, :ok}
    end

    test "upgrade_firmware/4 times out", %{device: device} do
      stub(Firmware, :download, fn _firmware -> {:ok, "/tmp/fw"} end)
      stub(Milesight, :upgrade_firmware, fn _url, _path, _opts -> :ok end)

      assert {:error, {:upgrade_timeout, "52.8.0.5"}} =
               Onvif.upgrade_firmware(device, @firmware, fn _ -> :ok end,
                 poll_interval: 1,
                 timeout: 10
               )
    end

    test "upgrade_firmware/4 stops on download errors", %{device: device} do
      stub(Firmware, :download, fn _firmware -> {:error, :checksum_mismatch} end)
      reject(Milesight, :upgrade_firmware, 3)

      test_pid = self()
      notify = &send(test_pid, {:progress, &1})

      assert {:error, :checksum_mismatch} = Onvif.upgrade_firmware(device, @firmware, notify)
      assert_received {:progress, {:error, :checksum_mismatch}}
      refute_received {:progress, :uploading}
    end
  end

  test "timezones" do
    assert {:ok, "EST5EDT,M3.2.0,M11.1.0"} = Timezones.posix("America/New_York")
    assert {:ok, "IST-5:30"} = Timezones.posix("Asia/Kolkata")
    assert {:ok, "UTC0"} = Timezones.posix("UTC")
    assert :error = Timezones.posix("Mars/Olympus")

    assert Timezones.country("America/New_York") == "US"
    # aliases resolve to the canonical zone country
    assert Timezones.country("US/Pacific") == "US"
    assert Timezones.country("Europe/Zagreb") == "HR"
    assert Timezones.country("UTC") == nil
    assert Timezones.country("Mars/Olympus") == nil
    assert Timezones.country(nil) == nil
  end
end
