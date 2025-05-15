defmodule ExNVR.Nerves.Monitoring.PowerSchedule do
  @moduledoc """
  Module responsible for monitoring power schedule retrieved from system settings
  and trigger an action (e.g. powering off the device outside the range of the schedule)
  """

  use GenServer, restart: :transient

  require Logger

  alias ExNVR.Devices
  alias ExNVR.Model.Schedule
  alias ExNVR.Nerves.SystemSettings

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting power schedule monitoring")
    Process.send_after(self(), :check_schedule, to_timeout(minute: 5))
    SystemSettings.subscribe()
    {:ok, get_settings()}
  end

  @impl true
  def handle_info(:check_schedule, state) do
    ntp_synced? = NervesTime.synchronized?()

    cond do
      is_nil(state.schedule) ->
        Process.send_after(self(), :check_schedule, to_timeout(minute: 5))

      not ntp_synced? or Schedule.scheduled?(state.schedule, DateTime.now!(state.timezone)) ->
        if not ntp_synced? do
          Logger.warning("[Power schedule]: NTP not synched, skipping schedule check")
        end

        Process.send_after(self(), :check_schedule, to_timeout(second: 15))

      true ->
        trigger_action(state.action)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:system_settings, :update}, _state) do
    {:noreply, get_settings()}
  end

  defp trigger_action("poweroff") do
    Logger.info("[Power schedule]: powering off the device")
    ExNVR.Events.create_event(%{type: "shutdown"})
    Enum.each(Devices.list(), &Devices.Supervisor.stop/1)
    Nerves.Runtime.poweroff()
  end

  defp trigger_action("stop_pipeline") do
    Logger.info("[Power schedule]: stopping all devices")
    Enum.each(Devices.list(), &Devices.Supervisor.stop/1)
  end

  defp trigger_action(action) do
    Logger.warning("[Power schedule]: unknown action #{inspect(action)}")
  end

  defp get_settings() do
    power_config = SystemSettings.get_settings().power_schedule

    %{
      power_config
      | schedule: power_config.schedule && Schedule.parse!(power_config.power_schedule)
    }
  end
end
