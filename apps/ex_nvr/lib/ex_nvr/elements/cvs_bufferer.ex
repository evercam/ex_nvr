defmodule ExNVR.Elements.CVSBufferer do
  @moduledoc """
  Element that buffers the last Coded Video Sequence (CVS) and sent it whenever
  an output pad is linked

  A use case of this element, is when we want to get a live snapshot from a
  stream, so instead of decoding the whole stream, we'll buffer the last CVS and
  decode it to get the latest snapshot
  """

  use Membrane.Filter

  alias Membrane.H264

  def_input_pad :input,
    demand_mode: :auto,
    demand_unit: :buffers,
    accepted_format: %H264{alignment: :au},
    availability: :always

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
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
  def handle_process(
        :input,
        %Membrane.Buffer{metadata: %{h264: %{key_frame?: true}}} = buffer,
        _ctx,
        state
      ) do
    {[], %{state | cvs: [buffer]}}
  end

  @impl true
  def handle_process(:input, %Membrane.Buffer{} = buffer, _ctx, state) do
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
