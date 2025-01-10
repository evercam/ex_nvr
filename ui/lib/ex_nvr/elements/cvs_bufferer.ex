defmodule ExNVR.Elements.CVSBufferer do
  @moduledoc """
  Element that buffers the last Coded Video Sequence (CVS) and sent it whenever
  an output pad is linked

  A use case of this element, is when we want to get a live snapshot from a
  stream, so instead of decoding the whole stream, we'll buffer the last CVS and
  decode it to get the latest snapshot
  """

  use Membrane.Sink

  require ExNVR.Utils

  alias ExNVR.Utils
  alias Membrane.{H264, H265}

  def_input_pad :input,
    flow_control: :auto,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      ),
    availability: :always

  @impl true
  def handle_init(_ctx, _options) do
    {[], %{cvs: [], decoder: nil, width: 0, height: 0}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    codec =
      case stream_format do
        %H264{} -> :h264
        %H265{} -> :h265
      end

    {[],
     %{
       state
       | decoder: ExNVR.Decoder.new!(codec),
         width: stream_format.width,
         height: stream_format.height
     }}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) when Utils.keyframe(buffer) do
    {[], %{state | cvs: [buffer]}}
  end

  @impl true
  def handle_buffer(:input, %Membrane.Buffer{} = buffer, _ctx, state) do
    {[], %{state | cvs: [buffer | state.cvs]}}
  end

  @impl true
  def handle_parent_notification(:snapshot, _ctx, state) do
    {:ok, snapshot} =
      state.cvs
      |> Enum.reverse()
      |> ExNVR.MediaUtils.decode_last(state.decoder)
      |> Map.get(:payload)
      |> Turbojpeg.yuv_to_jpeg(state.width, state.height, 75, :I420)

    {[notify_parent: {:snapshot, snapshot}], state}
  end
end
