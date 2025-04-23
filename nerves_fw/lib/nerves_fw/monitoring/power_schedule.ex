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

  def reload() do
    GenServer.cast(__MODULE__, :reload)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting power schedule monitoring")
    Process.send_after(self(), :check_schedule, to_timeout(minute: 5))
    {:ok, get_settings()}
  end

  @impl true
  def handle_cast(:reload, _state) do
    {:noreply, get_settings()}
  end

  @impl true
  def handle_info(:check_schedule, state) do
    cond do
      is_nil(state.schedule) ->
        Process.send_after(self(), :check_schedule, to_timeout(minute: 5))
        {:noreply, state}

      not NervesTime.synchronized?() ->
        Logger.warning("[Power schedule]: NTP not synched, skipping schedule check")
        Process.send_after(self(), :check_schedule, to_timeout(second: 15))
        {:noreply, state}

      Schedule.scheduled?(state.schedule, DateTime.now!(state.timezone)) ->
        Process.send_after(self(), :check_schedule, to_timeout(second: 15))
        {:noreply, state}

      true ->
        trigger_action(state.action)
    end
  end

  defp trigger_action("poweroff") do
    Logger.info("[Power schedule]: powering off the device")
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
    settings = SystemSettings.get_settings()

    %{
      schedule: settings.power_schedule && Schedule.parse!(settings.power_schedule),
      timezone: settings.schedule_timezone,
      action: settings.schedule_action
    }
  end
end
