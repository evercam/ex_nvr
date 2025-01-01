defmodule ExNVR.Elements.Recording do
  @moduledoc """
  An element that streams samples from the recordings chunks as if it is
  one big file.
  """

  use Membrane.Source

  require Membrane.Logger

  alias ExMP4.Helper
  alias ExNVR.Model.Device
  alias ExNVR.Pipeline
  alias ExNVR.Recordings.Concatenater

  @timescale :nanosecond

  def_options device: [
                spec: Device.t(),
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
    availability: :on_request,
    flow_control: :manual

  defmodule State do
    @moduledoc false

    defstruct device: nil,
              stream: nil,
              start_date: nil,
              end_date: nil,
              duration: nil,
              cat: nil
  end

  @impl true
  def handle_init(_ctx, options) do
    state = %State{
      device: options.device,
      stream: options.stream,
      start_date: options.start_date,
      end_date: options.end_date,
      duration: options.duration
    }

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    case Concatenater.new(state.device, state.stream, state.start_date) do
      {:ok, offset, cat} ->
        actions =
          Enum.map(Concatenater.tracks(cat), fn track ->
            {:notify_parent, {:new_track, track.id, Pipeline.Track.new(track)}}
          end)

        duration =
          if state.duration != 0,
            do: state.duration + Membrane.Time.milliseconds(offset),
            else: 0

        {actions, %{state | cat: cat, duration: duration}}

      {:error, :end_of_stream} ->
        {[], state}
    end
  end

  @impl true
  def handle_pad_added(Pad.ref(:video, id) = pad, _ctx, state) do
    track = get_track(state, id)

    stream_format =
      case track.media do
        :h264 -> %Membrane.H264{alignment: :au, width: track.width, height: track.height}
        :h265 -> %Membrane.H265{alignment: :au, width: track.width, height: track.height}
      end

    {[stream_format: {pad, stream_format}], state}
  end

  @impl true
  def handle_demand(Pad.ref(:video, id) = pad, demand, :buffers, _ctx, state) do
    track = get_track(state, id)
    demand = min(demand, 30)

    {buffers, cat} =
      Enum.reduce_while(1..demand, {[], state.cat}, fn _idx, {buffers, cat} ->
        with {:ok, {sample, timestamp}, cat} <- Concatenater.next_sample(cat, id),
             buffer <- map_sample_to_buffer(sample, track),
             :ok <- check_duration_and_end_date(state, buffer, timestamp) do
          {:cont, {[buffer | buffers], cat}}
        else
          {:error, _error} -> {:halt, {buffers, cat}}
        end
      end)

    buffers = Enum.reverse(buffers)
    state = %{state | cat: cat}

    if length(buffers) == demand do
      {[buffer: {pad, buffers}, redemand: pad], state}
    else
      {[buffer: {pad, buffers}, end_of_stream: pad], state}
    end
  end

  defp check_duration_and_end_date(%State{} = state, buffer, sample_timestamp) do
    cond do
      state.duration != 0 and buffer.dts > state.duration ->
        {:error, :end_of_stream}

      DateTime.compare(sample_timestamp, state.end_date) != :lt ->
        {:error, :end_of_stream}

      true ->
        :ok
    end
  end

  defp map_sample_to_buffer(sample, track) do
    %Membrane.Buffer{
      payload: sample.payload,
      dts: Helper.timescalify(sample.dts, track.timescale, @timescale),
      pts: Helper.timescalify(sample.pts, track.timescale, @timescale),
      metadata: %{track.media => %{key_frame?: sample.sync?}}
    }
  end

  defp get_track(state, track_id) do
    Concatenater.tracks(state.cat) |> Enum.find(&(&1.id == track_id))
  end
end
