defmodule ExNVR.Pipeline.Output.Socket do
  @moduledoc """
  Send snapshots through socket

  The format of the message is:
  ```
     0                   1                   2                   3
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                      Unix Timestamp                           |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                      Unix Timestamp                           |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |           Width               |         Height                |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |   Channels    |                                               |
    +-+-+-+-+-+-+-+-+                                               +
    |                       Snapshot Data                           |
    :                                                               :
    |                                                               +
    |                                                               |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  ```
  """

  use Membrane.Sink

  require ExNVR.Utils

  alias ExNVR.AV.Decoder
  alias Membrane.{H264, H265}
  alias Membrane.Time

  def_input_pad :input, accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au})

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{decoder: nil, sockets: [], pts_to_datetime: %{}, keyframe?: false}}
  end

  @impl true
  def handle_stream_format(:input, sf, %{old_stream_format: sf}, state), do: {[], state}

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    codec =
      case stream_format do
        %H264{} -> :h264
        %H265{} -> :hevc
      end

    decoder = Decoder.new(codec, out_format: :rgb24)

    {actions, state} =
      if state.decoder do
        state.decoder
        |> Decoder.flush()
        |> Enum.reduce(state, &send_frame/2)
      else
        {[], state}
      end

    {actions, %{state | decoder: decoder}}
  end

  @impl true
  def handle_parent_notification({:new_socket, socket}, _ctx, state) do
    {[], %{state | sockets: [socket | state.sockets]}}
  end

  @impl true
  def handle_buffer(:input, _buffer, _ctx, %{sockets: []} = state), do: {[], state}

  @impl true
  def handle_buffer(:input, buffer, ctx, %{keyframe?: false} = state)
      when ExNVR.Utils.keyframe(buffer) do
    handle_buffer(:input, buffer, ctx, %{state | keyframe?: true})
  end

  @impl true
  def handle_buffer(:input, _buffer, _ctx, %{keyframe?: false} = state), do: {[], state}

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    buffer = %{buffer | pts: convert_pts(buffer.pts)}

    case Decoder.decode(state.decoder, buffer.payload, pts: buffer.pts) do
      [frame] ->
        timestamp = buffer_timestamp(buffer.metadata[:timestamp])
        state = Map.update!(state, :pts_to_datetime, &Map.put(&1, buffer.pts, timestamp))
        send_frame(frame, state)

      _other ->
        {[], state}
    end
  end

  defp send_frame(frame, state) do
    {timestamp, pts_to_datetime} = Map.pop!(state.pts_to_datetime, frame.pts)

    message =
      <<Membrane.Time.as_milliseconds(timestamp, :round)::64, frame.width::16, frame.height::16,
        3::8, frame.data::binary>>

    sockets =
      Enum.reduce(state.sockets, [], fn socket, open_sockets ->
        case :gen_tcp.send(socket, message) do
          {:error, :closed} -> open_sockets
          _other -> [socket | open_sockets]
        end
      end)

    if Enum.empty?(sockets) do
      {[notify_parent: :no_sockets],
       %{state | sockets: sockets, pts_to_datetime: pts_to_datetime}}
    else
      {[], %{state | sockets: sockets, pts_to_datetime: pts_to_datetime}}
    end
  end

  defp buffer_timestamp(nil), do: Time.os_time()
  defp buffer_timestamp(datetime), do: Time.from_datetime(datetime)

  defp convert_pts(value), do: ExMP4.Helper.timescalify(value, Time.seconds(1), 90_000)
end
