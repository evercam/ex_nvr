defmodule ExNVR.Devices.OnvifTest do
  use ExUnit.Case, async: true

  import Mimic

  alias ExNVR.Devices.Cameras.{DateTimeSettings, Timezones}
  alias ExNVR.Devices.Cameras.HttpClient.Milesight
  alias ExNVR.Devices.Onvif
  alias ExNVR.Devices.Onvif.AutoConfig

  @device %ExOnvif.Device{manufacturer: "HIKVISION"}

  setup_all do
    Mimic.copy(ExOnvif.Devices)
    Mimic.copy(ExOnvif.Media2)
    Mimic.copy(Milesight)
  end

  setup do
    stub(ExOnvif.Media2, :get_profiles, fn _device -> {:error, :unavailable} end)
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
