defmodule ExNVR.Elements.RecordingBin do
  @moduledoc """
  Element responsible for reading recordings chunks as if it's one big file.

  Videos are recorded as 1-minute chunks on most cases, some pipelines
  needs to interact with the files as if it is one video file. This element
  will consolidate the video chunks into one big file by:
    * Reading the videos chunks
    * Correct dts/pts
    * Filter the recordings by start date, end date and duration
  """

  use Membrane.Bin

  require Membrane.Logger

  alias ExNVR.Recordings
  alias ExNVR.Elements.Recording.Timestamper
  alias Membrane.{File, H264, H265, MP4}

  @childs_to_delete [:source, :demuxer, :parser, :timestamper]

  def_options device: [
                spec: ExNVR.Model.Device.t(),
                description: "The device from where to read the recordings"
              ],
              stream: [
                spec: :high | :low,
                default: :high,
                description: "The stream type"
              ],
              start_date: [
                spec: DateTime.t(),
                description: "The start date of the recording"
              ],
              strategy: [
                spec: :keyframe_before | :keyframe_after | :exact,
                default: :keyframe_before,
                description: """
                The strategy to use for selecting the first buffer to pass.

                The following strategy are available:
                  * `keyframe_before` - the first buffer will be keyframe before the start date
                  * `keyframe_after` - the first buffer will be a keyframe after the start date
                  * `exact` - start from the exact timestamp even when the buffer is not a keyframe
                """
              ],
              end_date: [
                spec: DateTime.t(),
                default: ~U(2099-01-01 00:00:00Z),
                description: """
                The end date of the recording.

                Note that if both `duration` and `end_date` are provided, an
                `end_of_stream` will be sent on the first satisfied condition.
                """
              ],
              duration: [
                spec: Membrane.Time.t(),
                default: 0,
                description: """
                The total duration of the stream before sending `end_of_stream`.

                Note that if both `duration` and `end_date` are provided, an
                `end_of_stream` will be sent on the first satisfied condition.
                """
              ]

  def_output_pad :video,
    accepted_format:
      any_of(
        %Membrane.H264{alignment: :au},
        %Membrane.H265{alignment: :au}
      ),
    availability: :on_request

  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.debug("Initialize recording bin: #{inspect(options)}")

    recordings =
      Recordings.get_recordings_between(
        options.device.id,
        options.stream,
        options.start_date,
        options.end_date
      )

    state =
      Map.from_struct(options)
      |> Map.merge(%{
        recordings: recordings,
        current_recording: nil,
        recording_duration: 0,
        track: nil
      })

    {spec, state} = read_file_spec(state)
    {[spec: spec], state}
  end

  @impl true
  def handle_setup(_ctx, %{current_recording: nil} = state) do
    {[notify_parent: :no_recordings], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:video, _ref) = pad, _ctx, state) do
    track = state.track
    id = state.current_recording.id

    spec = [
      get_child({:demuxer, id})
      |> via_out(Pad.ref(:output, 1))
      |> add_depayloader(track, id)
      |> child({:timestamper, id}, %Timestamper{
        offset: state.recording_duration,
        start_date: Membrane.Time.from_datetime(state.current_recording.start_date)
      })
      |> child(:funnel, %Membrane.Funnel{end_of_stream: :never})
      |> child(:scissors, %ExNVR.Elements.Recording.Scissors{
        start_date: Membrane.Time.from_datetime(state.start_date),
        end_date: Membrane.Time.from_datetime(state.end_date),
        duration: state.duration,
        strategy: state.strategy
      })
      |> bin_output(pad)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:new_tracks, [{track_id, track}]}, {:demuxer, id}, ctx, state) do
    cond do
      is_nil(state.track) ->
        {[notify_parent: {:track, track}], %{state | track: track}}

      state.track != track ->
        Membrane.Logger.warning("""
        Recordings have different codecs or configuration
        Current track: "#{inspect(state.track)}"
        New track: "#{inspect(track)}"
        Send an end of stream
        """)

        {[remove_children: childs_to_delete(ctx), notify_child: {:scissors, :end_of_stream}],
         state}

      true ->
        spec = [
          get_child({:demuxer, id})
          |> via_out(Pad.ref(:output, track_id))
          |> add_depayloader(track, id)
          |> child({:timestamper, id}, %Timestamper{
            offset: state.recording_duration,
            start_date: Membrane.Time.from_datetime(state.current_recording.start_date)
          })
          |> get_child(:funnel)
        ]

        {[spec: spec], state}
    end
  end

  @impl true
  def handle_element_end_of_stream({:timestamper, id}, pad, ctx, %{recordings: []} = state) do
    recordings =
      Recordings.get_recordings_between(
        state.device.id,
        state.stream,
        state.current_recording.end_date,
        state.end_date
      )

    if recordings != [] do
      handle_element_end_of_stream({:timestamper, id}, pad, ctx, %{state | recordings: recordings})
    else
      {[remove_children: childs_to_delete(ctx), notify_child: {:scissors, :end_of_stream}], state}
    end
  end

  @impl true
  def handle_element_end_of_stream({:timestamper, _id}, _pad, ctx, state) do
    {spec, state} = read_file_spec(state)
    {[remove_children: childs_to_delete(ctx), spec: spec], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end

  defp read_file_spec(%{recordings: []} = state) do
    {[], state}
  end

  defp read_file_spec(%{recordings: [recording | rest]} = state) do
    Membrane.Logger.debug("Start reading file: #{recording.filename}")

    spec = [
      child({:source, recording.id}, %File.Source{
        location: Recordings.recording_path(state.device, state.stream, recording)
      })
      |> child({:demuxer, recording.id}, MP4.Demuxer.ISOM)
    ]

    state = update_recording_duration(state)

    {spec, %{state | recordings: rest, current_recording: recording}}
  end

  defp update_recording_duration(%{current_recording: nil} = state), do: state

  defp update_recording_duration(state) do
    start_date = Membrane.Time.from_datetime(state.current_recording.start_date)
    end_date = Membrane.Time.from_datetime(state.current_recording.end_date)
    duration = state.recording_duration + end_date - start_date

    %{state | recording_duration: duration}
  end

  defp childs_to_delete(ctx) do
    ctx.children
    |> Map.keys()
    |> Enum.filter(fn
      {name, _id} when name in @childs_to_delete -> true
      _other -> false
    end)
  end

  defp add_depayloader(link_builder, %H264{} = _track, id) do
    child(link_builder, {:parser, id}, %H264.Parser{
      repeat_parameter_sets: true,
      output_stream_structure: :annexb
    })
  end

  defp add_depayloader(link_builder, %H265{} = _track, id) do
    child(link_builder, {:parser, id}, %H265.Parser{
      repeat_parameter_sets: true,
      output_stream_structure: :annexb
    })
  end

  defp add_depayloader(link_builder, _track, _id), do: link_builder
end
