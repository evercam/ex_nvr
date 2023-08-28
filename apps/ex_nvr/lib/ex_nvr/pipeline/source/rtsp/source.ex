defmodule ExNVR.Pipeline.Source.RTSP.Source do
  @moduledoc """
  Element that starts an RTSP session and read packets from the same connection
  """

  use Membrane.Source
  use Bunch.Access

  require Membrane.Logger

  alias ExNVR.Pipeline.Source.RTSP.ConnectionManager
  alias Membrane.{Buffer, RemoteStream}

  @max_reconnect_attempts :infinity
  @reconnect_delay 3_000

  def_options stream_uri: [
                spec: binary(),
                default: nil,
                description: "A RTSP URI from where to read the stream"
              ],
              stream_types: [
                spec: [:video | :audio | :application],
                default: [:video, :audio, :application],
                description: "The type of stream to read"
              ]

  def_output_pad :output,
    accepted_format: %RemoteStream{type: :packetized},
    mode: :push,
    availability: :on_request

  @impl true
  def handle_init(_context, %__MODULE__{} = options) do
    {[],
     %{
       stream_uri: options[:stream_uri],
       stream_types: options[:stream_types],
       connection_manager: nil,
       buffers: [],
       play?: false,
       output_pad: nil
     }}
  end

  @impl true
  def handle_setup(_context, state) do
    {[], do_handle_setup(state)}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, _ref) = pad, _ctx, state) do
    buffers = Enum.map(state.buffers, &{:buffer, {pad, &1}}) |> Enum.reverse()
    state = %{state | output_pad: pad, play?: true}
    {[stream_format: {pad, %RemoteStream{type: :packetized}}] ++ buffers, state}
  end

  @impl true
  def handle_info({:rtsp_setup_complete, tracks}, _context, state) do
    {[notify_parent: {:rtsp_setup_complete, tracks}], state}
  end

  @impl true
  def handle_info({:media_packet, _channel, packet}, _ctx, %{play?: true} = state) do
    {[buffer: {state.output_pad, wrap_in_buffer(packet)}], state}
  end

  @impl true
  def handle_info({:media_packet, _channel, packet}, _ctx, state) do
    {[], %{state | buffers: [wrap_in_buffer(packet) | state.buffers]}}
  end

  @impl true
  def handle_info({:connection_info, {:connection_failed, error}}, _ctx, state) do
    Membrane.Logger.error("could not connect to RTSP server due to #{inspect(error)}")
    {connection_lost_actions(state), %{state | play?: false, buffers: []}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, _ctx, %{connection_manager: pid} = state) do
    Membrane.Logger.warning("connection manager exited due to #{inspect(reason)}, reconnect ...")
    {connection_lost_actions(state), do_handle_setup(state)}
  end

  @impl true
  def handle_info(_other, _context, state) do
    {[], state}
  end

  defp connection_lost_actions(%{play?: true} = state) do
    [event: {state.output_pad, %Membrane.Event.Discontinuity{}}, notify_parent: :connection_lost]
  end

  defp connection_lost_actions(_state), do: [notify_parent: :connection_lost]

  defp do_handle_setup(state) do
    {:ok, connection_manager} =
      ConnectionManager.start(
        endpoint: self(),
        stream_uri: state[:stream_uri],
        max_reconnect_attempts: @max_reconnect_attempts,
        reconnect_delay: @reconnect_delay,
        stream_types: state.stream_types
      )

    Process.monitor(connection_manager)

    %{state | connection_manager: connection_manager, play?: false, output_pad: nil}
  end

  defp wrap_in_buffer(packet) do
    %Buffer{payload: packet, metadata: %{arrival_ts: Membrane.Time.os_time()}}
  end
end
