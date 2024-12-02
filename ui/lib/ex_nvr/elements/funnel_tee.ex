defmodule ExNVR.Elements.FunnelTee do
  @moduledoc """
  An element that acts as a funnel and tee.

  Both input and output pads are dynamic. All the buffers from an input
  is forwarded to all outputs.

  An end of stream or input pad deletion will translate to an end of stream
  event on the outputs.
  """

  use Membrane.Filter

  alias ExNVR.Pipeline.Event.StreamClosed

  def_input_pad :video,
    accepted_format: _any,
    flow_control: :auto,
    availability: :on_request

  def_output_pad :video_output,
    accepted_format: _any,
    flow_control: :auto,
    availability: :on_request

  @impl true
  def handle_init(_ctx, _options) do
    {[], %{stream_format: nil}}
  end

  @impl true
  def handle_stream_format(Pad.ref(:video, _ref), stream_format, _ctx, state) do
    {[forward: stream_format], %{state | stream_format: stream_format}}
  end

  @impl true
  def handle_pad_added(
        Pad.ref(:video_output, _ref) = pad,
        _ctx,
        %{stream_format: stream_format} = state
      )
      when not is_nil(stream_format) do
    {[stream_format: {pad, stream_format}], state}
  end

  @impl true
  def handle_pad_added(_pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:video, _ref), ctx, state) do
    Map.keys(ctx.pads)
    |> Enum.filter(fn
      Pad.ref(:video_output, _ref) -> true
      _other -> false
    end)
    |> Enum.map(fn pad -> {:event, {pad, %StreamClosed{}}} end)
    |> then(&{&1, %{state | stream_format: nil}})
  end

  @impl true
  def handle_pad_removed(_pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_buffer(Pad.ref(:video, _ref), buffer, _ctx, state) do
    {[forward: buffer], state}
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    {[], state}
  end
end
