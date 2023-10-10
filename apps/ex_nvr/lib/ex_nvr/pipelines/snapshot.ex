defmodule ExNVR.Pipelines.Snapshot do
  @moduledoc """
  Pipeline responsible for retrieving a snapshot from an MP4 file
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias ExNVR.Elements
  alias ExNVR.Elements.RecordingBin

  def start(options) do
    Pipeline.start(__MODULE__, Keyword.put(options, :caller, self()))
  end

  @impl true
  def handle_init(_ctx, options) do
    Logger.metadata(device_id: options[:device_id])
    Membrane.Logger.info("Start snapshot pipeline with options: #{inspect(options)}")

    rank = if options[:method] == :precise, do: :last, else: :first

    spec = [
      child(:source, %RecordingBin{
        device_id: options[:device_id],
        start_date: options[:date],
        end_date: options[:date],
        strategy: :keyframe_before
      })
      |> via_out(:video)
      |> via_in(Pad.ref(:input, make_ref()),
        options: [format: options[:format] || :jpeg, rank: rank]
      )
      |> child(:sink, Elements.SnapshotBin)
    ]

    {[spec: spec], %{caller: options[:caller]}}
  end

  @impl true
  def handle_child_notification({:snapshot, snapshot}, :sink, _ctx, state) do
    Membrane.Logger.info("Got snapshot")
    send(state.caller, {:snapshot, snapshot})
    {[terminate: :shutdown], %{state | caller: nil}}
  end
end
