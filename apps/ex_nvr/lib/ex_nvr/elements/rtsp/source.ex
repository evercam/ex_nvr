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

  def_output_pad :output,
    accepted_format: %RemoteStream{type: :packetized},
    mode: :push,
    availability: :on_request

  @impl true
  def handle_init(_context, %__MODULE__{} = options) do
    {[],
     %{
       stream_uri: options[:stream_uri],
       connection_manager: nil,
       buffered_actions: [],
       output_ref: nil,
       play?: false
     }}
  end

  @impl true
  def handle_setup(_context, state) do
    {[], do_handle_setup(state)}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, ref), _ctx, %{output_ref: ref} = state) do
    actions =
      [stream_format: {Pad.ref(:output, ref), %RemoteStream{type: :packetized}}] ++
        Enum.reverse(state.buffered_actions)

    {actions, %{state | buffered_actions: [], play?: true}}
  end

  @impl true
  def handle_pad_added(_pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_playing(_context, state) do
    {[], state}
  end

  @impl true
  def handle_info({:rtsp_setup_complete, setup}, _context, state) do
    {[notify_parent: {:rtsp_setup_complete, setup, state.output_ref}], state}
  end

  @impl true
  def handle_info({:media_packet, packet}, _ctx, %{play?: true} = state) do
    {[buffer: {Pad.ref(:output, state.output_ref), packet_to_buffer(packet)}], state}
  end

  @impl true
  def handle_info({:media_packet, packet}, _ctx, state) do
    buffer_action = {:buffer, {Pad.ref(:output, state.output_ref), packet_to_buffer(packet)}}
    {[], %{state | buffered_actions: [buffer_action | state.buffered_actions]}}
  end

  @impl true
  def handle_info({:connection_info, {:connection_failed, error}}, _ctx, state) do
    Membrane.Logger.error("could not connect to RTSP server due to #{inspect(error)}")
    {connection_lost_actions(state), %{state | play?: false, output_ref: make_ref()}}
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

  defp connection_lost_actions(%{play?: true, output_ref: ref}) do
    [
      event: {Pad.ref(:output, ref), %Membrane.Event.Discontinuity{}},
      end_of_stream: Pad.ref(:output, ref),
      notify_parent: {:connection_lost, ref}
    ]
  end

  defp connection_lost_actions(_state), do: []

  defp do_handle_setup(state) do
    {:ok, connection_manager} =
      ConnectionManager.start(
        endpoint: self(),
        stream_uri: state[:stream_uri],
        max_reconnect_attempts: @max_reconnect_attempts,
        reconnect_delay: @reconnect_delay
      )

    Process.monitor(connection_manager)

    %{state | connection_manager: connection_manager, play?: false, output_ref: make_ref()}
  end

  defp packet_to_buffer(packet) do
    %Buffer{payload: packet, metadata: %{arrival_ts: Membrane.Time.os_time()}}
  end
end
