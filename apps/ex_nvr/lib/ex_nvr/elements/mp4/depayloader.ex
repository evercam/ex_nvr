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
                description: """
                The end date of the last access unit to get.

                Note that if this option and `duration` are provided,
                the first condition that's reached will cause the end
                of the stream
                """
              ],
              duration: [
                spec: Membrane.Time.t(),
                default: 0,
                description: """
                The total duration of the recordings to read.

                Once this duration is reached, an end of stream is sent
                by this element.

                Note that if this option and `end_date` are provided,
                the first condition that's reached will cause the end
                of the stream
                """
              ]

  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.debug("Initialize the element")

    state =
      Map.from_struct(options)
      |> Map.merge(%{
        last_recording_date: options.start_date,
        depayloader: nil,
        recordings: [],
        time_base: nil,
        current_dts: 0,
        last_access_unit_dts: nil,
        pending_buffers: [],
        buffer?: true,
        size_to_read: 0
      })

    {[], state}
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

  def handle_demand(:output, size, :buffers, _ctx, %{size_to_read: 0} = state) do
    {[redemand: :output], %{state | size_to_read: size}}
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

  defp map_buffers(%{time_base: {ticks, base}} = state, buffers, dts, pts, keyframes) do
    [buffers, dts, pts, keyframes]
    |> Enum.zip()
    |> Enum.map(fn {payload, dts, pts, key_frame?} ->
      dts = div(dts * base * Membrane.Time.second(), ticks)
      pts = div(pts * base * Membrane.Time.second(), ticks)

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

    state =
      if state.buffer? do
        %{state | pending_buffers: []}
      else
        %{
          state
          | current_dts: state.last_access_unit_dts || 0,
            last_access_unit_dts: nil
        }
      end

    {[redemand: :output], open_file(state)}
  end

  defp open_file(state) do
    Membrane.Logger.debug("Open current file: #{hd(state.recordings).filename}")

    filename = Path.join(Utils.recording_dir(state.device_id), hd(state.recordings).filename)
    {depayloader, time_base} = Native.open_file!(filename)

    %{state | depayloader: depayloader, time_base: time_base}
  end

  defp prepare_buffer_actions(buffers, %{buffer?: true} = state) do
    time_diff =
      state.start_date
      |> DateTime.diff(hd(state.recordings).start_date)
      |> Membrane.Time.seconds()
      |> max(0)

    last_dts = List.last(buffers).dts
    pending_buffers = Enum.reverse(buffers) ++ state.pending_buffers

    if last_dts >= time_diff do
      {first, second} = Enum.split_while(pending_buffers, &(not &1.metadata.key_frame?))

      # rewrite the dts/pts of the buffers so the buffers at the
      # requested start date will have dts/pts 0
      buffers =
        Enum.map(
          [hd(second) | Enum.reverse(first)],
          &%Buffer{&1 | dts: &1.dts - last_dts, pts: &1.pts - last_dts}
        )

      # Since we start from the nearest keyframe before the provided start date
      # we'll add the duration offset between the provided start date and the real start date
      duration =
        if state.duration > 0 do
          state.duration + last_dts - hd(first).dts
        else
          0
        end

      {[buffer: {:output, buffers}],
       %{
         state
         | buffer?: false,
           pending_buffers: [],
           last_access_unit_dts: 0,
           current_dts: -last_dts,
           duration: duration,
           size_to_read: max(0, state.size_to_read - length(buffers))
       }}
    else
      {[],
       %{
         state
         | pending_buffers: pending_buffers,
           last_access_unit_dts: last_dts
       }}
    end
  end

  defp prepare_buffer_actions(buffers, state) do
    state = %{
      state
      | last_access_unit_dts: List.last(buffers).dts,
        size_to_read: max(0, state.size_to_read - length(buffers))
    }

    {[buffer: {:output, buffers}] ++ maybe_end_stream(state), state}
  end

  defp maybe_end_stream(state) do
    start_date_ns = Membrane.Time.from_datetime(hd(state.recordings).start_date)
    end_date_ns = Membrane.Time.from_datetime(state.end_date)
    recording_duration = state.last_access_unit_dts - state.current_dts

    cond do
      state.duration > 0 and state.last_access_unit_dts >= state.duration ->
        [end_of_stream: :output]

      start_date_ns + recording_duration >= end_date_ns ->
        [end_of_stream: :output]

      true ->
        []
    end
  end

  defp maybe_redemand({actions, state}) do
    if Keyword.has_key?(actions, :end_of_stream) or state.size_to_read == 0 do
      {actions, state}
    else
      {actions ++ [redemand: :output], state}
    end
  end

  defp maybe_read_recordings(%{recordings: []} = state) do
    Membrane.Logger.debug(
      "fetch recordings between dates: #{inspect(state.last_recording_date)} - #{inspect(state.end_date)}"
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
