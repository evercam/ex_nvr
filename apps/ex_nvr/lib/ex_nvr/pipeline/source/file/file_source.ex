defmodule ExNVR.Pipeline.Source.File do
  @moduledoc """
  An Element responsible for streaming a file video.

  Options are:
    * location: which represens the video file's full path.
    * loop: a positive integer of how many times to loop the video, defaults to 0 (infinity).
  """

  use Membrane.Bin

  require Membrane.Logger

  alias ExNVR.Elements.Recording.Timestamper
  alias Membrane.MP4

  def_options location: [
                spec: String.t(),
                description: "The location of the video file"
              ],
              loop: [
                spec: non_neg_integer(),
                default: 0,
                description: "how many times to loop the video(0 means forever)"
              ]

  def_output_pad :video,
  demand_unit: :buffers,
  accepted_format: %Membrane.H264{alignment: :au}

  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.debug("Initialize the file source bin: #{inspect(options)}")

    state = Map.from_struct(options)
            |> Map.merge(%{
              file_duration: 0,
              file_creation_time: DateTime.utc_now()
            })

    {spec, state} = read_file_spec(state)

    spec =
      [
        child(:funnel, %Membrane.Funnel{end_of_stream: :never})
        |> child(:scissors, %ExNVR.Elements.Recording.Scissors{
          start_date: Membrane.Time.from_datetime(state.file_creation_time),
          duration: Membrane.Time.as_nanoseconds(state.file_duration),
          strategy: :exact
        })
        |> bin_output(:video)
      ] ++ spec

    IO.inspect(spec)

    {[spec: spec], state}
  end

  @impl true
  def handle_setup(_ctx, %{location: nil} = state) do
    {[notify_parent: :no_file], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    Membrane.Logger.debug("Setup the file source element, start streaming")

    {[notify_parent: {:started_streaming}], state}
  end

  @impl true
  def handle_child_notification({:new_tracks, [{track_id, track}]}, {:demuxer, id}, _ctx, state) do
    spec = [
      get_child({:demuxer, id})
      |> via_out(Pad.ref(:output, track_id))
      |> add_depayloader(track, id)
      |> child({:timestamper, id}, %Timestamper{
        offset: Membrane.Time.as_nanoseconds(state.file_duration),
        start_date: Membrane.Time.from_datetime(state.file_creation_time) #DateTime.utc_now())
      })
      |> get_child(:funnel)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_element_end_of_stream({:parser, id}, _pad, _ctx, %{loop: -1} = state) do
    IO.inspect("Looop Reached end '-1' ")
    {[remove_children: childs_to_delete(id), notify_child: {:scissors, :end_of_stream}], state}
    |> IO.inspect()
  end

  @impl true
  def handle_element_end_of_stream({:parser, id}, pad, ctx, %{loop: 1} = state) do
    IO.inspect("Looop Reached Last rep '1' ")
    {_, state} = read_file_spec(state)
    handle_element_end_of_stream({:parser, id}, pad, ctx, %{state | loop: -1})
  end

  @impl true
  def handle_element_end_of_stream({:parser, id}, pad, ctx, state) do
    if state.loop not in [0, -1, 1] do
      {_spec, state} = read_file_spec(state)
      handle_element_end_of_stream({:parser, id}, pad, ctx, %{state | loop: state.loop - 1})
    end
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end

  defp read_file_spec(%{location: nil} = state) do
    {[], state}
  end

  defp read_file_spec(%{location: file_path} = state) do
    Membrane.Logger.debug("Start reading file: #{file_path}")
    {_creation_time, _modification_time, _timescale, duration, _next_track_id} =
      File.open!(file_path)
      |> IO.binread(112)
      |> extract_meta()

    state = %{state | file_duration: state.file_duration + duration}
            |> IO.inspect()
    id = UUID.uuid4()
    spec = [
      child({:source, id}, %Membrane.File.Source{location: file_path})
      |> child({:demuxer, id}, MP4.Demuxer.ISOM)
    ]

    {spec, state}
  end

  defp childs_to_delete(id) do
    IO.inspect("Deleting children of #{id}")
    [:source, :demuxer, :depayloader, :parser, :timestamper] |> Enum.map(&{&1, id})
  end

  defp add_depayloader(link_builder, %Membrane.MP4.Payload.AVC1{} = _track, id) do
    link_builder
    |> child({:depayloader, id}, Membrane.MP4.Depayloader.H264)
    |> child({:parser, id}, %Membrane.H264.Parser{
      repeat_parameter_sets: true
    })
  end

  defp add_depayloader(link_builder, _track, _id), do: link_builder

  defp extract_meta(<<0::integer-32-big, rest::binary>>) do
    <<
      creation_time::integer-32-big,
      modification_time::integer-32-big,
      timescale::integer-32-big,
      duration::integer-32-big,
      _skip::binary-size(76),
      next_track_id::integer-32-big
    >> = rest

    {creation_time, modification_time, timescale, duration, next_track_id}
  end

  defp extract_meta(<<_version::integer-32-big, rest::binary >>) do
    <<
      creation_time::integer-64-big,
      modification_time::integer-64-big,
      timescale::integer-32-big,
      duration::integer-64-big,
      _skip::binary-size(76),
      next_track_id::integer-32-big
    >> = rest

    {creation_time, modification_time, timescale, duration, next_track_id}
  end
end
