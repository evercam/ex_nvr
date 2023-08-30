defmodule ExNVR.Pipeline.Output.Bif.KeyFrameSelector do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.{H264, Time}

  def_options interval: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.seconds(10),
                description: "Interval between key frames"
              ]

  def_input_pad :input,
    demand_mode: :auto,
    demand_unit: :buffers,
    accepted_format: %H264{alignment: :au},
    availability: :always

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :always

  defguardp key_frame?(buffer) when buffer.metadata.h264.key_frame?

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{interval: Time.round_to_seconds(opts.interval), last_keyframe_pts: nil}}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) when key_frame?(buffer) do
    if is_nil(state.last_keyframe_pts) or diff(buffer, state) >= state.interval do
      {[buffer: {:output, buffer}],
       %{state | last_keyframe_pts: Time.round_to_seconds(buffer.pts)}}
    else
      {[], state}
    end
  end

  @impl true
  def handle_process(:input, _buffer, _ctx, state) do
    {[], state}
  end

  defp diff(buffer, state) do
    Membrane.Time.round_to_seconds(buffer.pts) - state.last_keyframe_pts
  end
end
