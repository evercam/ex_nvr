defmodule ExNVR.Pipeline.Output.Bif.KeyFrameSelector do
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
    demand_mode: :auto,
    demand_unit: :buffers,
    accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au}),
    availability: :always

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au}),
    availability: :always

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{interval: Time.round_to_seconds(opts.interval), last_keyframe_pts: nil}}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) when ExNVR.Utils.keyframe(buffer) do
    if is_nil(state.last_keyframe_pts) or diff(buffer, state) >= state.interval do
      pts = rem(buffer.metadata.timestamp, 3600 * 10 ** 9)
      state = %{state | last_keyframe_pts: Time.round_to_seconds(buffer.pts)}

      {[buffer: {:output, %{buffer | pts: pts}}], state}
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
