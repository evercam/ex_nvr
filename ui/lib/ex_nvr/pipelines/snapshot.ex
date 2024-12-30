defmodule ExNVR.Pipelines.Snapshot do
  @moduledoc """
  Pipeline responsible for retrieving a snapshot from an MP4 file
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias ExNVR.Elements
  alias ExNVR.Elements.Recording

  def start(options) do
    Pipeline.start(__MODULE__, Keyword.put(options, :caller, self()))
  end

  @impl true
  def handle_init(_ctx, options) do
    Logger.metadata(device_id: options[:device].id)
    Membrane.Logger.info("Start snapshot pipeline with options: #{inspect(options)}")

    rank = if options[:method] == :precise, do: :last, else: :first

    spec = [
      child(:source, %Recording{
        device: options[:device],
        start_date: options[:date],
        end_date: options[:date]
      })
    ]

    {[spec: spec], %{caller: options[:caller], rank: rank, format: options[:format] || :jpeg}}
  end

  @impl true
  def handle_child_notification({:new_track, track_id, track}, :source, _ctx, state) do
    spec = [
      get_child(:source)
      |> via_out(Pad.ref(:video, track_id))
      |> via_in(Pad.ref(:input, make_ref()),
        options: [format: state.format, rank: state.rank, encoding: track.encoding]
      )
      |> child(:sink, Elements.SnapshotBin)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:snapshot, snapshot}, :sink, _ctx, state) do
    Membrane.Logger.info("Got snapshot")
    send(state.caller, {:snapshot, snapshot})
    {[terminate: :shutdown], %{state | caller: nil}}
  end
end
