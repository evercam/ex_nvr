defmodule ExNVR.Pipelines.Snapshot do
  @moduledoc """
  Pipeline responsible for retrieving a snapshot from an MP4 file
  """

  use Membrane.Pipeline

  alias Membrane.H264
  alias ExNVR.Elements
  alias ExNVR.Elements.MP4

  def start_link(options) do
    Pipeline.start_link(__MODULE__, Keyword.put(options, :caller, self()))
  end

  @impl true
  def handle_init(_ctx, options) do
    rank = if options[:method] == :precise, do: :last, else: :first

    spec = [
      child(:source, %MP4.Depayloader{
        device_id: options[:device_id],
        start_date: options[:date],
        end_date: options[:date]
      })
      |> child(:parser, H264.Parser)
      |> via_in(Pad.ref(:input, make_ref()),
        options: [format: options[:format] || :jpeg, rank: rank]
      )
      |> child(:sink, Elements.SnapshotBin)
    ]

    {[spec: spec, playback: :playing], %{caller: options[:caller]}}
  end

  @impl true
  def handle_child_notification({:snapshot, snapshot}, :sink, _ctx, state) do
    send(state.caller, {:snapshot, snapshot})
    {[terminate: :shutdown], %{state | caller: nil}}
  end
end
