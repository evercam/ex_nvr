defmodule ExNVR.Pipelines.MainPipelineTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import Membrane.Testing.Assertions

  alias ExNVR.{Devices, Utils}
  alias ExNVR.Pipeline.Track
  alias ExNVR.Pipelines.Main, as: MainPipeline
  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}
  alias Membrane.Testing

  @moduletag :tmp_dir

  setup do
    %{device: file_device_fixture(%{state: :failed})}
  end

  test "main pipeline", %{device: device} do
    pid = prepare_pipeline(device)

    socket_server =
      if elem(:os.type(), 0) == :unix do
        File.mkdir(Utils.unix_socket_dir())
        assert {:ok, socket_server} = ExNVR.UnixSocketServer.start(device: device)
        socket_server
      end

    # pipeline notifications
    assert_pipeline_notified(
      pid,
      :file_source,
      {:main_stream, 1, %Track{type: :video, encoding: :H264}}
    )

    assert Devices.get!(device.id).state == :streaming

    # allow some time for the buffers to propagate to the different
    # elements in the main pipeline
    Process.sleep(1_000)

    # Live snapshot
    assert {:ok, snapshot} = MainPipeline.live_snapshot(device, :jpeg)

    assert {:ok, %Turbojpeg.JpegHeader{width: 480, height: 240, format: :I420}} =
             Turbojpeg.get_jpeg_header(snapshot)

    # Unix Socket

    if elem(:os.type(), 0) == :unix do
      unix_socket_path = Utils.unix_socket_path(device.id) |> to_charlist()

      assert {:ok, socket} =
               :gen_tcp.connect({:local, unix_socket_path}, 0, [:binary, active: false])

      assert_pipeline_receive(pid, {:new_socket, _socket})

      assert {:ok, <<_timestamp::64, 480::16, 240::16, 3::8, _data::binary>>} =
               :gen_tcp.recv(socket, 0, :timer.seconds(5))

      assert :ok = :gen_tcp.close(socket)

      assert_pipeline_notified(pid, :unix_socket, :no_sockets)

      Process.exit(socket_server, :kill)
    end

    # WebRTC
    assert {:ok, pc} = PeerConnection.start()
    assert :ok = MainPipeline.add_webrtc_peer(device, :high)
    assert {:error, :stream_unavailable} = MainPipeline.add_webrtc_peer(device, :low)

    assert_receive {:offer, offer}, 1_000
    assert :ok = PeerConnection.set_remote_description(pc, SessionDescription.from_json(offer))

    {:ok, answer} = PeerConnection.create_answer(pc)
    :ok = PeerConnection.set_local_description(pc, answer)

    :ok =
      MainPipeline.forward_peer_message(
        device,
        :high,
        {:answer, SessionDescription.to_json(answer)}
      )

    assert_receive {:ex_webrtc, ^pc, {:ice_candidate, ice_candidate}}, 2_000

    :ok =
      MainPipeline.forward_peer_message(
        device,
        :high,
        {:ice_candidate, ICECandidate.to_json(ice_candidate)}
      )

    assert_receive {:ex_webrtc, ^pc, {:connection_state_change, :connected}}, 2_000

    assert_receive {:ex_webrtc, ^pc,
                    {:rtp, _track_id, nil, %ExRTP.Packet{payload_type: 96, version: 2}}},
                   1_000

    assert :ok = PeerConnection.close(pc)

    # HLS
    hls_dir = Path.join(Utils.hls_dir(device.id), "live")

    assert_pipeline_notified(pid, :hls_sink, {:track_playable, :main_stream})

    assert File.exists?(hls_dir)
    assert Path.join(hls_dir, "*.mp4") |> Path.wildcard() |> length() == 1

    # TODO: test rtsp sources and add tests for storage.
    # by default file sources are not stored on the filesystem.

    assert :ok = Testing.Pipeline.terminate(pid)
  end

  defp prepare_pipeline(device) do
    options = [
      module: ExNVR.Pipelines.Main,
      custom_args: [device: device],
      name: ExNVR.Utils.pipeline_name(device)
    ]

    Testing.Pipeline.start_link_supervised!(options)
  end
end
