defmodule ExNVR.Elements.MP4.Depayloader do
  @moduledoc """
  An Element responsible for reading MP4 files and extracting NAL units.

  It uses FFmpeg and NIF to do the job.
  """

  use Membrane.Source

  require Membrane.Logger

  alias ExNVR.Elements.MP4.Depayloader.Native
  alias ExNVR.Recordings
  alias Membrane.{Buffer, H264}

  def_output_pad :output,
    demand_mode: :manual,
    accepted_format: %H264.RemoteStream{alignment: :au},
    availability: :always

  def_options start_date: [
                spec: DateTime.t(),
                description: """
                The start date from which we start getting access units from recordings.

                It'll start from the nearest keyframe before the specified date time to
                avoid decoding the video stream.
                """
              ]

  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.debug("Initialize the element")

    {[],
     %{
       start_date: options.start_date,
       recordings: [],
       depayloader: nil,
       frame_rate: nil,
       current_file: nil,
       current_pts: 0,
       last_access_unit_pts: nil
     }}
  end

  @impl true
  def handle_setup(_ctx, state) do
    Membrane.Logger.debug("Setup the element: fetch recordings after date #{inspect(state.start_date)}")

    state =
      case Recordings.get_recordings_after(state.start_date) do
        [first_recoding | rest] ->
          %{state | recordings: rest, current_file: first_recoding.filename}

        _ ->
          state
      end

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state), do: open_file(state)

  @impl true
  def handle_demand(:output, _size, :buffers, _ctx, %{frame_rate: {frames, seconds}} = state) do
    case Native.read_access_unit(state.depayloader) do
      {:ok, buffers, pts} ->
        buffers =
          buffers
          |> Enum.zip(pts)
          |> Enum.map(fn {payload, pts} ->
            pts = div(pts * seconds * Membrane.Time.second(), frames)
            %Buffer{payload: payload, pts: pts + state.current_pts}
          end)

        {[buffer: {:output, buffers}, redemand: :output],
         %{state | last_access_unit_pts: List.last(buffers).pts}}

      {:error, _reason} ->
        maybe_read_next_file(state)
    end
  end

  defp maybe_read_next_file(%{recordings: []} = state) do
    Membrane.Logger.debug("Read all available recordings, sending end of stream")
    {[end_of_stream: :output], state}
  end

  defp maybe_read_next_file(%{recordings: [next_recording | rest]} = state) do
    Membrane.Logger.debug("Reached end of file of the current file")

    state = %{
      state
      | recordings: rest,
        current_file: next_recording.filename,
        current_pts: state.last_access_unit_pts,
        last_access_unit_pts: nil
    }

    {actions, state} = open_file(state)

    {actions ++ [redemand: :output], state}
  end

  defp open_file(state) do
    Membrane.Logger.debug("Open current file: #{state.current_file}")

    filename = Path.join(recording_directory(), state.current_file)
    {depayloader, frame_rate} = Native.open_file!(filename)

    {[stream_format: {:output, %H264.RemoteStream{alignment: :au}}],
     %{state | depayloader: depayloader, frame_rate: frame_rate}}
  end

  defp recording_directory(), do: Application.get_env(:ex_nvr, :recording_directory)
end
