defmodule ExNVR.Elements.RTSP.Source do
  @moduledoc """
  Element that starts an RTSP session and read packets from the same connection
  """

  use Membrane.Source
  use Bunch.Access

  require Membrane.Logger

  alias ExNVR.Elements.RTSP.ConnectionManager
  alias Membrane.{Buffer, RemoteStream}

  @max_reconnect_attempts :infinity
  @reconnect_delay 3_000

  def_options stream_uri: [
                spec: binary(),
                default: nil,
                description: "A RTSP URI from where to read the stream"
              ]

  def_output_pad :output, accepted_format: %RemoteStream{type: :packetized}, mode: :push

  @impl true
  def handle_init(_context, %__MODULE__{} = options) do
    {[], %{stream_uri: options[:stream_uri], connection_manager: nil, buffered_actions: []}}
  end

  @impl true
  def handle_setup(_context, state) do
    {[], do_handle_setup(state)}
  end

  @impl true
  def handle_playing(_context, state) do
    actions =
      [stream_format: {:output, %RemoteStream{type: :packetized}}] ++
        Enum.reverse(state.buffered_actions)

    {actions, %{state | buffered_actions: []}}
  end

  @impl true
  def handle_info({:rtsp_setup_complete, _setup} = msg, _context, state) do
    {[notify_parent: msg], state}
  end

  @impl true
  def handle_info({:media_packet, packet}, %{playback: :playing}, state) do
    {[buffer: {:output, packet_to_buffer(packet)}], state}
  end

  @impl true
  def handle_info({:media_packet, packet}, _ctx, state) do
    {[],
     %{
       state
       | buffered_actions: [
           {:buffer, {:output, packet_to_buffer(packet)}} | state.buffered_actions
         ]
     }}
  end

  @impl true
  def handle_info({:connection_info, {:connection_failed, error}}, ctx, state) do
    Membrane.Logger.error("could not connect to RTSP server due to #{inspect(error)}")
    {connection_lost_actions(ctx), state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, ctx, %{connection_manager: pid} = state) do
    Membrane.Logger.warn("connection manager exited due to #{inspect(reason)}, reconnect ...")
    {connection_lost_actions(ctx), do_handle_setup(state)}
  end

  @impl true
  def handle_info(_other, _context, state) do
    {[], state}
  end

  defp connection_lost_actions(%{playback: state}) do
    if state == :playing do
      [event: {:output, %Membrane.Event.Discontinuity{}}, notify_parent: :connection_lost]
    else
      [notify_parent: :connection_lost]
    end
  end

  defp do_handle_setup(state) do
    {:ok, connection_manager} =
      ConnectionManager.start(
        endpoint: self(),
        stream_uri: state[:stream_uri],
        max_reconnect_attempts: @max_reconnect_attempts,
        reconnect_delay: @reconnect_delay
      )

    Process.monitor(connection_manager)

    %{state | connection_manager: connection_manager}
  end

  defp packet_to_buffer(packet) do
    %Buffer{payload: packet, metadata: %{arrival_ts: Membrane.Time.vm_time()}}
  end
end
