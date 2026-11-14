defmodule ExNVR.PipelineStarter do
  @moduledoc """
  Starts the device recording pipelines once at boot.

  This replaces a previous unsupervised one-shot `Task`. Starting the pipelines
  reads the devices from the database and prepares storage directories; both can
  fail transiently at boot (database momentarily locked, storage not yet
  mounted). Rather than dying and leaving the NVR running while recording
  nothing — booting "healthy" but never recording — this process retries with a
  capped backoff and only stops once the pipelines have been started.
  """

  use GenServer

  require Logger

  @default_initial_backoff to_timeout(second: 1)
  @default_max_backoff to_timeout(second: 30)

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      # Stops `:normal` once the pipelines are started, so a transient restart
      # does not re-run it; an unexpected crash is still retried.
      restart: :transient
    }
  end

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @impl true
  def init(opts) do
    state = %{
      start_fun: Keyword.get(opts, :start_fun, &ExNVR.start/0),
      backoff: Keyword.get(opts, :initial_backoff, @default_initial_backoff),
      max_backoff: Keyword.get(opts, :max_backoff, @default_max_backoff)
    }

    # Do the work outside `init/1` so the supervision tree boots without
    # blocking on the database / filesystem.
    send(self(), :start)
    {:ok, state}
  end

  @impl true
  def handle_info(:start, state) do
    case run(state.start_fun) do
      :ok ->
        {:stop, :normal, state}

      {:error, formatted} ->
        Logger.error("""
        Failed to start device pipelines, retrying in #{state.backoff}ms
        #{formatted}
        """)

        Process.send_after(self(), :start, state.backoff)
        {:noreply, %{state | backoff: min(state.backoff * 2, state.max_backoff)}}
    end
  end

  defp run(start_fun) do
    start_fun.()
    :ok
  rescue
    error -> {:error, Exception.format(:error, error, __STACKTRACE__)}
  catch
    kind, reason -> {:error, Exception.format(kind, reason, __STACKTRACE__)}
  end
end
