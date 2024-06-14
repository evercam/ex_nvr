defmodule ExNVR.Pipeline.Output.Thumbnailer.KeyFrameSelector do
  @moduledoc false

  use Membrane.Filter

  require ExNVR.Utils

  alias Membrane.{H264, H265, Time}

  def_options interval: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.seconds(10),
                description: "Interval between key frames"
              ]

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au}),
    availability: :always

  def_output_pad :output,
    flow_control: :auto,
    accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au}),
    availability: :always

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{interval: Time.as_seconds(opts.interval, :round), last_keyframe_pts: nil}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) when ExNVR.Utils.keyframe(buffer) do
    if is_nil(state.last_keyframe_pts) or diff(buffer, state) >= state.interval do
      state = %{state | last_keyframe_pts: Time.as_seconds(buffer.pts, :round)}
      {[buffer: {:output, buffer}], state}
    else
      {[], state}
    end
  end

  @impl true
  def handle_buffer(:input, _buffer, _ctx, state) do
    {[], state}
  end

  defp diff(buffer, state) do
    Membrane.Time.as_seconds(buffer.pts, :round) - state.last_keyframe_pts
  end
end
