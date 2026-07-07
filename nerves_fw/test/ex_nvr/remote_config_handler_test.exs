defmodule ExNVR.Nerves.RemoteConfigHandlerTest do
  @moduledoc false
  use ExNVR.DataCase, async: false

  import Mimic

  alias ExNVR.Hardware
  alias ExNVR.Nerves.Giraffe.Init
  alias ExNVR.Nerves.{RemoteConfigHandler, RUT, SystemSettings}

  @moduletag :tmp_dir
  @moduletag capture_log: true

  setup :set_mimic_global
  setup :verify_on_exit!

  setup_all do
    Mimic.copy(RUT)
    Mimic.copy(Init)
    Mimic.copy(Hardware.SerialPortChecker)
    :ok
  end

  setup %{tmp_dir: tmp_dir} do
    start_supervised!({SystemSettings, [path: Path.join(tmp_dir, "settings.json")]})
    on_exit(fn -> Application.put_env(:ex_nvr_fw, :target, :host) end)
    :ok
  end

  describe "handle_message/2" do
    test "ignores incoming config when the kit is not configured" do
      reject(&RUT.set_scheduler/1)
      reject(&Hardware.SerialPortChecker.enable/0)
      reject(&Hardware.SerialPortChecker.disable/0)
      reject(&Init.set_ups/1)

      assert :ok = RemoteConfigHandler.handle_message("config", %{"power_type" => "solar"})

      assert SystemSettings.get_settings().power_type == :other
    end

    test "updates the router schedule when the power schedule changes" do
      mark_configured()
      expect(RUT, :set_scheduler, fn _schedule -> :ok end)

      config = %{"power_schedule" => %{"schedule" => %{"1" => ["10:00-15:00"]}}}
      RemoteConfigHandler.handle_message("config", config)

      assert SystemSettings.get_settings().power_schedule.schedule == %{"1" => ["10:00-15:00"]}
    end

    test "does not update the router schedule when the power schedule is unchanged" do
      mark_configured()
      reject(&RUT.set_scheduler/1)

      RemoteConfigHandler.handle_message("config", %{"router" => %{"username" => "user"}})

      assert SystemSettings.get_settings().router.username == "user"
    end

    test "enables serial port checker and updates ups when power type is solar on giraffe" do
      mark_configured()
      Application.put_env(:ex_nvr_fw, :target, :giraffe)

      expect(Hardware.SerialPortChecker, :enable, fn -> :ok end)
      expect(Init, :set_ups, fn :solar -> :ok end)

      RemoteConfigHandler.handle_message("config", %{"power_type" => "solar"})
      assert SystemSettings.get_settings().power_type == :solar
    end

    test "disables serial port checker and updates ups when power type is mains on giraffe" do
      mark_configured()
      Application.put_env(:ex_nvr_fw, :target, :giraffe)

      expect(Hardware.SerialPortChecker, :disable, fn -> :ok end)
      expect(Init, :set_ups, fn :mains -> :ok end)

      RemoteConfigHandler.handle_message("config", %{"power_type" => "mains"})

      assert SystemSettings.get_settings().power_type == :mains
    end

    test "does not update ups on non-giraffe targets" do
      mark_configured()

      expect(Hardware.SerialPortChecker, :enable, fn -> :ok end)
      reject(&Init.set_ups/1)

      RemoteConfigHandler.handle_message("config", %{"power_type" => "generator"})

      assert SystemSettings.get_settings().power_type == :generator
    end

    test "does not run power type handlers when the power type is unchanged" do
      mark_configured()

      reject(&Hardware.SerialPortChecker.enable/0)
      reject(&Hardware.SerialPortChecker.disable/0)
      reject(&Init.set_ups/1)

      RemoteConfigHandler.handle_message("config", %{"power_type" => "other"})

      assert SystemSettings.get_settings().power_type == :other
    end
  end

  defp mark_configured do
    {:ok, _settings} = SystemSettings.update(%{configured: true})
  end
end
