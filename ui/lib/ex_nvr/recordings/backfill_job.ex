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

  @type status :: %{
          started_at: DateTime.t(),
          start_date: DateTime.t(),
          end_date: DateTime.t(),
          min_gap: pos_integer()
        }

  @spec start(Device.t(), DateTime.t(), DateTime.t(), pos_integer()) ::
          {:ok, pid()} | {:error, :already_running | any()}
  def start(%Device{} = device, start_date, end_date, min_gap) do
    case DynamicSupervisor.start_child(
           __MODULE__.Supervisor,
           {__MODULE__,
            device: device, start_date: start_date, end_date: end_date, min_gap: min_gap}
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

    status =
      args
      |> Keyword.take([:start_date, :end_date, :min_gap])
      |> Map.new()
      |> Map.put(:started_at, DateTime.utc_now())

    GenServer.start_link(__MODULE__, args,
      name: {:via, Registry, {__MODULE__.Registry, device.id, status}}
    )
  end

  @impl true
  def init(args) do
    device = Keyword.fetch!(args, :device)
    broadcast(device, :started)

    {:ok, args |> Keyword.take([:device, :start_date, :end_date, :min_gap]) |> Map.new(),
     {:continue, :run}}
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
    Backfiller.run(state.device, state.start_date, state.end_date, min_gap: state.min_gap * 60)
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp broadcast(device, event) do
    Phoenix.PubSub.broadcast(ExNVR.PubSub, topic(device.id), {:backfill, event})
  end
end
