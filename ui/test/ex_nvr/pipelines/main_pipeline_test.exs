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

  # Outputs that aren't part of the recording path each run in their own crash group
  # (see ExNVR.Pipelines.Main.isolated_child/3); the recording spine
  # (source -> tee -> storage) must survive any of them crashing.
  @spine [:file_source, :tee]

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
      {:main_stream, %{1 => %Track{type: :video, encoding: :h264}}}
    )

    assert Devices.get!(device.id).state == :streaming

    # allow some time for the buffers to propagate to the different
    # elements in the main pipeline
    Process.sleep(1_000)

    # Live snapshot
    assert {:ok, snapshot} = MainPipeline.live_snapshot(device, :jpeg)
    assert is_binary(snapshot)

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
    assert {:ok, _codec} = MainPipeline.add_webrtc_peer(device, :high)
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

    assert_pipeline_notified(pid, :hls_sink, {:track_playable, nil})

    assert File.exists?(hls_dir)
    assert Path.join([hls_dir, "video", "*.mp4"]) |> Path.wildcard() |> length() == 1

    assert :ok = Testing.Pipeline.terminate(pid)
  end

  describe "crash isolation" do
    test "crashing the WebRTC output does not take down the pipeline or recording spine",
         %{device: device} do
      pid = start_streaming_pipeline(device)

      spine = capture_spine(pid)
      sibling = {:snapshooter, :main_stream}
      sibling_pid = await_child(pid, sibling)
      webrtc_pid = await_child(pid, :webrtc)

      watch(pid, spine)

      Process.exit(webrtc_pid, :kill)

      # Nothing on the recording spine (nor the pipeline) is torn down.
      refute_receive {:DOWN, _ref, :process, _pid, _reason}, 1_000

      assert_unchanged(pid, spine)
      # Per-output isolation: a sibling output is undisturbed too.
      assert {:ok, ^sibling_pid} = Testing.Pipeline.get_child_pid(pid, sibling)
    end

    test "crashing the HLS output does not take down the pipeline or recording spine",
         %{device: device} do
      pid = start_streaming_pipeline(device)

      spine = capture_spine(pid)
      webrtc_pid = await_child(pid, :webrtc)

      watch(pid, spine)

      hls_pid = await_child(pid, :hls_sink)
      Process.exit(hls_pid, :kill)

      refute_receive {:DOWN, _ref, :process, _pid, _reason}, 1_000

      assert_unchanged(pid, spine)
      assert {:ok, ^webrtc_pid} = Testing.Pipeline.get_child_pid(pid, :webrtc)
    end
  end

  describe "crash recovery" do
    test "a crashed WebRTC output is re-spawned", %{device: device} do
      pid = start_streaming_pipeline(device)
      webrtc_pid = await_child(pid, :webrtc)

      Process.exit(webrtc_pid, :kill)

      new_pid = await_respawn(pid, :webrtc, webrtc_pid)
      assert Process.alive?(new_pid)
    end

    test "a crashed HLS output is re-spawned", %{device: device} do
      pid = start_streaming_pipeline(device)
      hls_pid = await_child(pid, :hls_sink)

      Process.exit(hls_pid, :kill)

      new_pid = await_respawn(pid, :hls_sink, hls_pid)
      assert Process.alive?(new_pid)
    end
  end

  defp prepare_pipeline(device) do
    options = [
      module: ExNVR.Pipelines.Main,
      custom_args: [device: device],
      name: ExNVR.Utils.pipeline_name(device)
    ]

    Testing.Pipeline.start_link_supervised!(options)
  end

  defp start_streaming_pipeline(device) do
    pid = prepare_pipeline(device)
    # Wait until the main-stream track is seen; this is what triggers building the tee
    # and the per-output children.
    assert_pipeline_notified(pid, :file_source, {:main_stream, _tracks})
    pid
  end

  defp capture_spine(pid), do: Map.new(@spine, &{&1, await_child(pid, &1)})

  defp watch(pid, spine) do
    Process.monitor(pid)
    for {_child, child_pid} <- spine, do: Process.monitor(child_pid)
    :ok
  end

  defp assert_unchanged(pid, spine) do
    for {child, original} <- spine do
      assert {:ok, ^original} = Testing.Pipeline.get_child_pid(pid, child)
    end
  end

  defp await_child(pid, child, timeout \\ 5_000) do
    await(timeout, "child #{inspect(child)} did not start", fn ->
      case Testing.Pipeline.get_child_pid(pid, child) do
        {:ok, child_pid} -> {:ok, child_pid}
        {:error, _reason} -> :retry
      end
    end)
  end

  defp await_respawn(pid, child, old_pid, timeout \\ 3_000) do
    await(timeout, "child #{inspect(child)} was not re-spawned", fn ->
      case Testing.Pipeline.get_child_pid(pid, child) do
        {:ok, new_pid} when new_pid != old_pid -> {:ok, new_pid}
        _ -> :retry
      end
    end)
  end

  defp await(timeout, message, fun) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await(deadline, message, fun)
  end

  defp do_await(deadline, message, fun) do
    case fun.() do
      {:ok, value} ->
        value

      :retry ->
        if System.monotonic_time(:millisecond) > deadline do
          flunk(message)
        else
          Process.sleep(25)
          do_await(deadline, message, fun)
        end
    end
  end
end
