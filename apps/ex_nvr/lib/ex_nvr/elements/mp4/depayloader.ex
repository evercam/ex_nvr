defmodule ExNVR.Elements.MP4.Depayloader do
  @moduledoc """
  An Element responsible for reading recordings files and extracting access units.

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
       last_recording_date: options.start_date,
       recordings: [],
       depayloader: nil,
       frame_rate: nil,
       current_pts: 0,
       last_access_unit_pts: nil,
       pending_buffers: [],
       buffer?: true
     }}
  end

  @impl true
  def handle_setup(_ctx, state) do
    Membrane.Logger.debug("Setup the element, start fetching recordings")
    {[], maybe_read_recordings(state)}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {actions, state} = maybe_read_next_file(state)
    {[stream_format: {:output, %H264.RemoteStream{alignment: :au}}] ++ actions, state}
  end

  @impl true
  def handle_demand(:output, _size, :buffers, _ctx, %{frame_rate: {frames, seconds}} = state) do
    case Native.read_access_unit(state.depayloader) do
      {:ok, buffers, pts, keyframes} ->
        buffers =
          [buffers, pts, keyframes]
          |> Enum.zip()
          |> Enum.map(fn {payload, pts, key_frame?} ->
            pts = div(pts * seconds * Membrane.Time.second(), frames)

            %Buffer{
              payload: payload,
              pts: pts + state.current_pts,
              metadata: %{key_frame?: key_frame?}
            }
          end)

        {actions, state} = prepare_buffer_actions(state, buffers)
        {actions ++ [redemand: :output], state}

      {:error, _reason} ->
        state = maybe_read_recordings(%{state | recordings: tl(state.recordings)})
        maybe_read_next_file(state)
    end
  end

  defp maybe_read_next_file(%{recordings: []} = state) do
    Membrane.Logger.debug("Read all available recordings, sending end of stream")
    {[end_of_stream: :output], state}
  end

  defp maybe_read_next_file(state) do
    Membrane.Logger.debug("Reached end of file of the current file")

    state = %{
      state
      | current_pts: state.last_access_unit_pts || 0,
        last_access_unit_pts: nil
    }

    {[redemand: :output], open_file(state)}
  end

  defp open_file(state) do
    Membrane.Logger.debug("Open current file: #{hd(state.recordings).filename}")

    filename = Path.join(recording_directory(), hd(state.recordings).filename)
    {depayloader, frame_rate} = Native.open_file!(filename)

    %{state | depayloader: depayloader, frame_rate: frame_rate}
  end

  defp prepare_buffer_actions(%{buffer?: true} = state, buffers) do
    time_diff =
      DateTime.diff(state.start_date, hd(state.recordings).start_date) |> Membrane.Time.seconds()

    last_pts = List.last(buffers).pts

    if last_pts >= time_diff do
      Enum.concat(buffers, state.pending_buffers)
      |> Enum.split_while(&(not &1.metadata.key_frame?))
      |> then(fn {first, second} -> [hd(second) | Enum.reverse(first)] end)
      |> then(
        &{[buffer: {:output, &1}],
         %{state | buffer?: false, last_access_unit_pts: last_pts, pending_buffers: []}}
      )
    else
      {[],
       %{
         state
         | pending_buffers: buffers ++ state.pending_buffers,
           last_access_unit_pts: last_pts
       }}
    end
  end

  defp prepare_buffer_actions(state, buffers) do
    {[buffer: {:output, buffers}], %{state | last_access_unit_pts: List.last(buffers).pts}}
  end

  defp maybe_read_recordings(%{recordings: []} = state) do
    Membrane.Logger.debug(
      "fetch recordings after date: date=#{inspect(state.last_recording_date)}"
    )

    case Recordings.get_recordings_after(state.last_recording_date) do
      [] ->
        state

      recordings ->
        %{state | recordings: recordings, last_recording_date: List.last(recordings).end_date}
    end
  end

  defp maybe_read_recordings(state), do: state

  defp recording_directory(), do: Application.get_env(:ex_nvr, :recording_directory)
end
