defmodule ExNVR.Elements.MP4.Depayloader do
  @moduledoc """
  An Element responsible for reading recordings files and extracting access units.

  It uses FFmpeg and NIF to do the job.
  """

  use Membrane.Source

  require Membrane.Logger

  alias ExNVR.Elements.MP4.Depayloader.Native
  alias ExNVR.{Recordings, Utils}
  alias Membrane.{Buffer, H264}

  def_output_pad :output,
    demand_mode: :manual,
    accepted_format: %H264.RemoteStream{alignment: :au},
    availability: :always

  def_options device_id: [
                spec: binary(),
                description: "The device id"
              ],
              start_date: [
                spec: DateTime.t(),
                description: """
                The start date from which we start getting access units from recordings.

                It'll start from the nearest keyframe before the specified date time to
                avoid decoding the video stream.
                """
              ],
              end_date: [
                spec: DateTime.t(),
                default: ~U(2099-01-01 00:00:00Z),
                description: "The end date of the last access unit to get."
              ]

  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.debug("Initialize the element")

    {[],
     %{
       device_id: options.device_id,
       start_date: options.start_date,
       end_date: options.end_date,
       last_recording_date: options.start_date,
       recordings: [],
       depayloader: nil,
       frame_rate: nil,
       current_dts: 0,
       last_access_unit_dts: nil,
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
  def handle_demand(:output, _size, :buffers, _ctx, state) do
    case Native.read_access_unit(state.depayloader) do
      {:ok, buffers, dts, pts, keyframes} ->
        map_buffers(state, buffers, dts, pts, keyframes)
        |> prepare_buffer_actions(state)
        |> maybe_redemand()

      {:error, _reason} ->
        state = maybe_read_recordings(%{state | recordings: tl(state.recordings)})
        maybe_read_next_file(state)
    end
  end

  defp map_buffers(%{frame_rate: {frames, seconds}} = state, buffers, dts, pts, keyframes) do
    [buffers, dts, pts, keyframes]
    |> Enum.zip()
    |> Enum.map(fn {payload, dts, pts, key_frame?} ->
      dts = div(dts * seconds * Membrane.Time.second(), frames)
      pts = div(pts * seconds * Membrane.Time.second(), frames)

      %Buffer{
        payload: payload,
        dts: dts + state.current_dts,
        pts: pts + state.current_dts,
        metadata: %{key_frame?: key_frame?}
      }
    end)
  end

  defp maybe_read_next_file(%{recordings: []} = state) do
    Membrane.Logger.debug("Read all available recordings, sending end of stream")
    {[end_of_stream: :output], state}
  end

  defp maybe_read_next_file(state) do
    Membrane.Logger.debug("Reached end of file of the current file")

    state = %{
      state
      | current_dts: state.last_access_unit_dts || 0,
        last_access_unit_dts: nil
    }

    {[redemand: :output], open_file(state)}
  end

  defp open_file(state) do
    Membrane.Logger.debug("Open current file: #{hd(state.recordings).filename}")

    filename = Path.join(Utils.recording_dir(state.device_id), hd(state.recordings).filename)
    {depayloader, frame_rate} = Native.open_file!(filename)

    %{state | depayloader: depayloader, frame_rate: frame_rate}
  end

  defp prepare_buffer_actions(buffers, %{buffer?: true} = state) do
    time_diff =
      DateTime.diff(state.start_date, hd(state.recordings).start_date) |> Membrane.Time.seconds()

    last_dts = List.last(buffers).dts
    pending_buffers = Enum.reverse(buffers) ++ state.pending_buffers

    if last_dts >= time_diff do
      {first, second} = Enum.split_while(pending_buffers, &(not &1.metadata.key_frame?))

      # rewrite the pts of the buffers as the hd(second) will have dts of 0
      first_dts = hd(second).dts

      buffers =
        Enum.map(
          [hd(second) | Enum.reverse(first)],
          &%Buffer{&1 | dts: &1.dts - first_dts, pts: &1.pts - first_dts}
        )

      {[buffer: {:output, buffers}],
       %{
         state
         | buffer?: false,
           pending_buffers: [],
           last_access_unit_dts: last_dts - first_dts,
           current_dts: -first_dts
       }}
    else
      {[],
       %{
         state
         | pending_buffers: buffers ++ state.pending_buffers,
           last_access_unit_dts: last_dts
       }}
    end
  end

  defp prepare_buffer_actions(buffers, state) do
    last_access_unit_dts = List.last(buffers).dts

    {[buffer: {:output, buffers}] ++ maybe_end_stream(state, last_access_unit_dts),
     %{state | last_access_unit_dts: last_access_unit_dts}}
  end

  defp maybe_end_stream(state, last_access_unit_dts) do
    start_date_ns = Membrane.Time.from_datetime(state.start_date)
    end_date_ns = Membrane.Time.from_datetime(state.end_date)

    if start_date_ns + last_access_unit_dts >= end_date_ns do
      [end_of_stream: :output]
    else
      []
    end
  end

  defp maybe_redemand({actions, state}) do
    if Keyword.has_key?(actions, :end_of_stream) do
      {actions, state}
    else
      {actions ++ [redemand: :output], state}
    end
  end

  defp maybe_read_recordings(%{recordings: []} = state) do
    Membrane.Logger.debug(
      "fetch recordings after date: date=#{inspect(state.last_recording_date)}"
    )

    case Recordings.get_recordings_between(
           state.device_id,
           state.last_recording_date,
           state.end_date
         ) do
      [] ->
        state

      recordings ->
        %{state | recordings: recordings, last_recording_date: List.last(recordings).end_date}
    end
  end

  defp maybe_read_recordings(state), do: state
end
