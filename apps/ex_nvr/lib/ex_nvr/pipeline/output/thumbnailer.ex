defmodule ExNVR.Pipeline.Output.Thumbnailer do
  @moduledoc """
  Generate thumbnails at regular interval. The element will only decode keyframes at the expense of exact timestamps.
  """

  use Membrane.Bin

  require Membrane.Logger

  alias __MODULE__.{KeyFrameSelector, Sink}
  alias Membrane.{FFmpeg, H264, H265}

  def_input_pad :input,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      )

  def_options interval: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.seconds(10),
                description: """
                The rate of thumbnails generation.
                Defaults to one thumbnail per 10 seconds.
                """
              ],
              thumbnail_width: [
                spec: non_neg_integer(),
                default: 320,
                description: "The width of the generated thumbnail"
              ],
              dest: [
                spec: Path.t(),
                description: "The destination folder where the thumbnails will be stored"
              ],
              encoding: [
                spec: :H264 | :H265,
                description: "The codec used to compress the frames"
              ]

  @interval Membrane.Time.seconds(5)

  @impl true
  def handle_init(_ctx, options) do
    state = Map.from_struct(options)

    spec = [bin_input() |> child(:tee, Membrane.Tee.Parallel)]

    case check_directory(state.dest) do
      :ok ->
        {[spec: spec, spec: get_spec(state)], state}

      {:error, reason} ->
        Membrane.Logger.error(
          "Could not make directory or directory not writable '#{state.dest}', error: #{inspect(reason)}"
        )

        {[spec: spec, start_timer: {:check_directory, @interval}], state}
    end
  end

  @impl true
  def handle_element_end_of_stream(:sink, _pad, _ctx, state) do
    {[notify_parent: :end_of_stream], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_tick(:check_directory, _ctx, state) do
    case check_directory(state.dest) do
      :ok ->
        {[spec: get_spec(state), stop_timer: :check_directory], state}

      _error ->
        {[], state}
    end
  end

  @impl true
  def handle_crash_group_down(_group_name, _ctx, state) do
    Membrane.Logger.error("crash in thumbnailer")
    {[start_timer: {:check_directory, @interval}], state}
  end

  defp get_spec(state) do
    {[
       get_child(:tee)
       |> child(:key_frame_selector, %KeyFrameSelector{interval: state.interval})
       |> child(:decoder, get_decoder(state.encoding))
       |> child(:scaler, %FFmpeg.SWScale.Scaler{
         output_width: state.thumbnail_width,
         use_shm?: true
       })
       |> child(:image_encoder, Turbojpeg.Filter)
       |> child(:sink, %Sink{dest: state.dest})
     ], group: make_ref(), crash_group_mode: :temporary}
  end

  defp get_decoder(:H264), do: %H264.FFmpeg.Decoder{use_shm?: true}
  defp get_decoder(:H265), do: %H265.FFmpeg.Decoder{use_shm?: true}

  defp check_directory(dest) do
    if File.exists?(dest), do: ExNVR.Utils.writable(dest), else: File.mkdir(dest)
  end
end
