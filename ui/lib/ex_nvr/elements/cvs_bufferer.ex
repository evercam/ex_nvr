defmodule ExNVR.Elements.CVSBufferer do
  @moduledoc """
  Element that buffers the last Coded Video Sequence (CVS) and sent it whenever
  an output pad is linked

  A use case of this element, is when we want to get a live snapshot from a
  stream, so instead of decoding the whole stream, we'll buffer the last CVS and
  decode it to get the latest snapshot
  """

  use Membrane.Filter

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

  def_output_pad :output,
    flow_control: :auto,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      ),
    availability: :on_request

  @impl true
  def handle_init(_ctx, _options) do
    {[], %{cvs: [], stream_format: nil}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[], %{state | stream_format: stream_format}}
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
  def handle_pad_added(Pad.ref(:output, _ref) = pad, _ctx, state) do
    actions =
      state.cvs
      |> Enum.reverse()
      |> Enum.map(&{:buffer, {pad, &1}})

    {[stream_format: {pad, state.stream_format}] ++ actions ++ [end_of_stream: pad], state}
  end
end
