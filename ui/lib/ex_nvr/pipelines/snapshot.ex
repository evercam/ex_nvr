defmodule ExNVR.Pipelines.Snapshot do
  @moduledoc """
  Pipeline responsible for retrieving a snapshot from an MP4 file
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias ExNVR.Elements
  alias ExNVR.Elements.RecordingBin
  alias Membrane.{H264, H265}

  def start(options) do
    Pipeline.start(__MODULE__, Keyword.put(options, :caller, self()))
  end

  @impl true
  def handle_init(_ctx, options) do
    Logger.metadata(device_id: options[:device].id)
    Membrane.Logger.info("Start snapshot pipeline with options: #{inspect(options)}")

    rank = if options[:method] == :precise, do: :last, else: :first

    spec = [
      child(:source, %RecordingBin{
        device: options[:device],
        start_date: options[:date],
        end_date: options[:date],
        strategy: :keyframe_before
      })
    ]

    {[spec: spec], %{caller: options[:caller], rank: rank, format: options[:format] || :jpeg}}
  end

  @impl true
  def handle_child_notification({:track, track}, :source, _ctx, state) do
    encoding =
      case track do
        %H264{} -> :H264
        %H265{} -> :H265
      end

    spec = [
      get_child(:source)
      |> via_out(:video)
      |> via_in(Pad.ref(:input, make_ref()),
        options: [format: state.format, rank: state.rank, encoding: encoding]
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
