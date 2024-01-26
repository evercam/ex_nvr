defmodule ExNVR.Pipeline.Source.File do
  @moduledoc """
  An Element responsible for streaming a file video indefinitely.
  """

  use Membrane.Bin

  require Membrane.Logger

  alias ExNVR.Elements.Recording.Timestamper
  alias ExNVR.Model.Device
  alias Membrane.MP4

  def_options device: [
                spec: Device.t(),
                description: "The file device"
              ]

  def_output_pad :video,
    demand_unit: :buffers,
    accepted_format:
      any_of(
        %Membrane.H264{alignment: :au},
        %Membrane.H265{alignment: :au}
      )

  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.debug("Initialize the file source bin: #{inspect(options)}")

    state =
      %{
        location: Device.file_location(options.device),
        duration: Device.file_duration(options.device),
        iteration: 0
      }

    spec =
      [
        child(:funnel, %Membrane.Funnel{end_of_stream: :never})
        |> child(:realtimer, Membrane.Realtimer)
        |> bin_output(:video)
      ] ++ read_file_spec(state)

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:new_tracks, tracks}, {:demuxer, id}, _ctx, state) do
    spec_list =
      Enum.map(tracks, fn {track_id, track} ->
        case track do
          %Membrane.H264{} ->
            encoding = :H264

            spec =
              get_child({:demuxer, id})
              |> via_out(Pad.ref(:output, track_id))
              |> child({:parser, id}, %Membrane.H264.Parser{
                repeat_parameter_sets: true,
                output_stream_structure: :annexb
              })
              |> child({:timestamper, id}, %Timestamper{
                offset: state.iteration * state.duration,
                start_date: Membrane.Time.os_time()
              })
              |> get_child(:funnel)

            {spec, encoding}

          %Membrane.H265{} ->
            encoding = :H265

            spec =
              get_child({:demuxer, id})
              |> via_out(Pad.ref(:output, track_id))
              |> child({:parser, id}, %Membrane.H265.Parser{
                repeat_parameter_sets: true,
                output_stream_structure: :annexb
              })
              |> child({:timestamper, id}, %Timestamper{
                offset: state.iteration * state.duration,
                start_date: Membrane.Time.os_time()
              })
              |> get_child(:funnel)

            {spec, encoding}

          track ->
            Membrane.Logger.warning("""
            Not supported track, ignoring
            #{inspect(track)}
            """)

            encoding = :unknown

            spec =
              get_child({:demuxer, id})
              |> via_out(Pad.ref(:output, track_id))
              |> child({:realtimer, id}, Membrane.Realtimer)
              |> child({:fake_sink, id}, Membrane.Fake.Sink.Buffers)

            {spec, encoding}
        end
      end)

    {spec, encoding} = hd(spec_list)

    {[notify_parent: {:new_tracks, encoding}, spec: spec], state}
  end

  @impl true
  def handle_element_end_of_stream({:timestamper, id}, _pad, ctx, state) do
    childs_to_remove =
      ctx.children
      |> Map.keys()
      |> Enum.filter(fn
        {_name, ^id} -> true
        _other -> false
      end)

    {[remove_children: childs_to_remove, spec: read_file_spec(state)],
     %{state | iteration: state.iteration + 1}}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end

  defp read_file_spec(%{location: location}) do
    Membrane.Logger.info("Start reading file: #{location}")

    ref = make_ref()

    [
      child({:source, ref}, %Membrane.File.Source{location: location, seekable?: true})
      |> child({:demuxer, ref}, %MP4.Demuxer.ISOM{
        optimize_for_non_fast_start?: true
      })
    ]
  end
end
