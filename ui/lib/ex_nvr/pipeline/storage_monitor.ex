defmodule ExNVR.Pipeline.StorageMonitor do
  @moduledoc """
  Module responsible for notifying main pipeline if storage is allowed or not.
  """

  use GenServer

  require Logger

  alias ExNVR.Model.{Device, Schedule}
  alias ExNVR.Utils

  def start_link(opts) do
    opts = Keyword.put_new(opts, :pipeline_pid, self())
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    device = Keyword.fetch!(opts, :device)
    schedule = device.storage_config.schedule

    state = %{
      pipeline_pid: Keyword.fetch!(opts, :pipeline_pid),
      device: device,
      schedule: schedule && Schedule.parse!(schedule),
      dir: Device.base_dir(device),
      schedule_timer: nil,
      dir_timer: nil,
      record?: nil
    }

    {:ok, state, {:continue, :record?}}
  end

  @impl true
  def handle_continue(:record?, state) do
    case Utils.writable(state.dir) do
      :ok ->
        state
        |> notify_parent(record?(state))
        |> maybe_start_schedule_timer()
        |> then(&{:noreply, &1})

      {:error, reason} ->
        Logger.error("Destination '#{state.dir}' is not writable, error: #{inspect(reason)}")
        {:ok, dir_timer} = :timer.send_interval(to_timeout(second: 5), :check_dir)
        state = notify_parent(%{state | dir_timer: dir_timer}, false)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:check_dir, state) do
    case Utils.writable(state.dir) do
      :ok ->
        :timer.cancel(state.dir_timer)

        %{state | dir_timer: nil}
        |> notify_parent(record?(state))
        |> maybe_start_schedule_timer()
        |> then(&{:noreply, &1})

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:check_schedule, state) do
    state
    |> notify_parent(record?(state))
    |> then(&{:noreply, &1})
  end

  defp maybe_start_schedule_timer(%{schedule: nil} = state), do: state

  defp maybe_start_schedule_timer(state) do
    {:ok, schedule_timer} = :timer.send_interval(to_timeout(second: 5), :check_schedule)
    %{state | schedule_timer: schedule_timer}
  end

  defp notify_parent(%{record?: record?} = state, record?), do: state

  defp notify_parent(state, record?) do
    send(state.pipeline_pid, {:storage_monitor, :record?, record?})
    %{state | record?: record?}
  end

  defp record?(%{schedule: nil}), do: true

  defp record?(%{schedule: schedule} = state) do
    Schedule.scheduled?(schedule, DateTime.now!(state.device.timezone))
  end
end
