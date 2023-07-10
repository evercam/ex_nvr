defmodule ExNVR.Devices.Room do
  @moduledoc """
  An RTC engine for broadcasting device's streams using WebRTC
  """

  use GenServer

  require Logger

  alias Membrane.ICE.TURNManager
  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.WebRTC

  @mix_env Mix.env()

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def add_peer(server, channel_pid, peer_id) do
    GenServer.call(server, {:add_peer, {channel_pid, peer_id}})
  end

  @impl true
  def init(opts) do
    device = opts[:device]

    turn_options = integrated_turn_options()

    network_options = [
      integrated_turn_options: turn_options,
      integrated_turn_domain: Application.fetch_env!(:ex_nvr, :integrated_turn_domain),
      dtls_pkey: Application.get_env(:ex_nvr, :dtls_pkey),
      dtls_cert: Application.get_env(:ex_nvr, :dtls_cert)
    ]

    turn_tcp_port = Application.fetch_env!(:ex_nvr, :integrated_turn_tcp_port)
    TURNManager.ensure_tcp_turn_launched(turn_options, port: turn_tcp_port)

    {:ok, rtc_engine} = Engine.start_link([id: device.id], [])
    Engine.register(rtc_engine, self())

    stream_endpoint = %ExNVR.Devices.Room.StreamEndpoint{device: opts[:device]}
    stream_endpoint_id = UUID.uuid4()
    Engine.add_endpoint(rtc_engine, stream_endpoint, id: stream_endpoint_id)

    {:ok,
     %{
       rtc_engine: rtc_engine,
       device: device,
       network_options: network_options,
       peer_channels: %{},
       stream_endpoint_id: stream_endpoint_id
     }}
  end

  @impl true
  def handle_call({:add_peer, {channel_pid, peer_id}}, _from, %{rtc_engine: engine} = state) do
    state = put_in(state, [:peer_channels, peer_id], channel_pid)

    handshake_opts =
      if state.network_options[:dtls_key] && state.network_options[:dtls_cert] do
        [
          client_mode: false,
          dtls_srtp: true,
          pkey: state.network_options[:dtls_key],
          cert: state.network_options[:dtls_cert]
        ]
      else
        [
          client_mode: false,
          dtls_srtp: true
        ]
      end

    webrtc_endpoint = %WebRTC{
      rtc_engine: engine,
      direction: :recv,
      ice_name: peer_id,
      owner: self(),
      integrated_turn_options: state.network_options[:integrated_turn_options],
      handshake_opts: handshake_opts,
      webrtc_extensions: [Membrane.WebRTC.Extension.TWCC]
    }

    Engine.add_endpoint(engine, webrtc_endpoint, id: peer_id)

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:media_event, peer_id, media_event}, %{rtc_engine: engine} = state) do
    Engine.message_endpoint(engine, peer_id, {:media_event, media_event})
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Engine.Message.EndpointMessage{
          endpoint_id: endpoint_id,
          message: {:media_event, media_event}
        },
        state
      ) do
    channel_pid = state.peer_channels[endpoint_id]
    send(channel_pid, {:media_event, media_event})
    {:noreply, state}
  end

  @impl true
  def handle_info({:video_track, _video_track} = message, state) do
    Engine.message_endpoint(state.rtc_engine, state.stream_endpoint_id, message)
    {:noreply, state}
  end

  @impl true
  def handle_info(:connection_lost, state) do
    Engine.message_endpoint(state.rtc_engine, state.stream_endpoint_id, :connection_lost)
    {:noreply, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.warn("Received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  defp integrated_turn_options() do
    turn_mock_ip = Application.fetch_env!(:ex_nvr, :integrated_turn_ip)
    turn_ip = if @mix_env == :prod, do: {0, 0, 0, 0}, else: turn_mock_ip

    turn_cert_file =
      case Application.fetch_env(:ex_nvr, :integrated_turn_cert_pkey) do
        {:ok, val} -> val
        :error -> nil
      end

    [
      ip: turn_ip,
      mock_ip: turn_mock_ip,
      ports_range: Application.fetch_env!(:ex_nvr, :integrated_turn_port_range),
      cert_file: turn_cert_file
    ]
  end
end
