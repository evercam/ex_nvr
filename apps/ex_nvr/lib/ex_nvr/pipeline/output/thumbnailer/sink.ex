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
    File.write!(get_filename(state.dest, buffer), buffer.payload)
    {[], state}
  end

  defp get_filename(dest_folder, buffer) do
    if Application.get_env(:ex_nvr, :env) == :test do
      Path.join(dest_folder, "#{Membrane.Buffer.get_dts_or_pts(buffer)}.jpg")
    else
      Path.join(dest_folder, "#{DateTime.utc_now() |> DateTime.to_unix()}.jpg")
    end
  end
end
