defmodule ExNVR.Pipeline.Output.Thumbnailer.Sink do
  @moduledoc """
  A sink element that saves the snapshots with the timestamp as name
  """

  use Membrane.Sink

  def_input_pad :input, flow_control: :auto, accepted_format: _any

  def_options dest: [
                spec: Path.t(),
                description: "The location where to save the thumbnails"
              ]

  @impl true
  def handle_init(_ctx, options) do
    {[], Map.from_struct(options)}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    path =
      Path.join(
        state.dest,
        "#{Membrane.Time.to_datetime(buffer.pts) |> DateTime.to_unix()}.jpg"
      )

    File.write!(path, buffer.payload)
    {[], state}
  end
end
