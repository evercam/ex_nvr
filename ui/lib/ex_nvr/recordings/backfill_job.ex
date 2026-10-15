defmodule ExNVR.Recordings.BackfillJob do
  @moduledoc """
  Run `ExNVR.Recordings.Backfiller` in the background, at most one job per device.

  Job events are broadcasted on `topic/1` as `{:backfill, event}` where event is one of
  `:started`, `{:completed, [Run.t()]}` or `{:failed, reason}`.
  """

  use GenServer

  require Logger

  alias ExNVR.Model.Device
  alias ExNVR.Recordings.Backfiller

  # older than any footage a camera may have
  @camera_storage_start ~U(2000-01-01 00:00:00Z)

  @type status :: %{started_at: DateTime.t(), min_gap: pos_integer()}

  @spec start(Device.t(), pos_integer()) :: {:ok, pid()} | {:error, :already_running | any()}
  def start(%Device{} = device, min_gap) do
    case DynamicSupervisor.start_child(
           __MODULE__.Supervisor,
           {__MODULE__, device: device, min_gap: min_gap}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :already_running}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Get the running job of the device, `min_gap` is in minutes."
  @spec status(Device.t()) :: status() | nil
  def status(%Device{id: device_id}) do
    case Registry.lookup(__MODULE__.Registry, device_id) do
      [{_pid, status}] -> status
      [] -> nil
    end
  end

  @spec topic(binary()) :: binary()
  def topic(device_id), do: "backfill:#{device_id}"

  def child_spec(args) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [args]}, restart: :temporary}
  end

  def start_link(args) do
    device = Keyword.fetch!(args, :device)
    status = %{started_at: DateTime.utc_now(), min_gap: Keyword.fetch!(args, :min_gap)}

    GenServer.start_link(__MODULE__, args,
      name: {:via, Registry, {__MODULE__.Registry, device.id, status}}
    )
  end

  @impl true
  def init(args) do
    device = Keyword.fetch!(args, :device)
    broadcast(device, :started)
    {:ok, %{device: device, min_gap: Keyword.fetch!(args, :min_gap)}, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, %{device: device} = state) do
    Logger.info("[BackfillJob] start backfilling device #{device.id}")

    event =
      case run(state) do
        {:ok, runs} ->
          Logger.info("[BackfillJob] device #{device.id} backfilled with #{length(runs)} runs")
          {:completed, runs}

        {:error, reason} ->
          Logger.error("[BackfillJob] device #{device.id} backfill failed: #{inspect(reason)}")
          {:failed, reason}
      end

    broadcast(device, event)

    {:stop, :normal, state}
  end

  defp run(state) do
    Backfiller.run(state.device, @camera_storage_start, DateTime.utc_now(),
      min_gap: state.min_gap * 60
    )
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp broadcast(device, event) do
    Phoenix.PubSub.broadcast(ExNVR.PubSub, topic(device.id), {:backfill, event})
  end
end
