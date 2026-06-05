defmodule ExNVR.Pipeline.Output.WebRTCTest do
  @moduledoc """
  Regression tests for the WebRTC sink's handling of stale or out-of-order
  signaling. A peer (the channel process) and its peer connection can go away
  at any time; messages referencing them must be dropped instead of crashing
  the sink, which would tear down the whole device pipeline.

  These tests exercise the sink's callbacks directly with a handcrafted state,
  no real peer connections needed for the guard paths.
  """

  use ExUnit.Case, async: true

  alias ExNVR.Pipeline.Output.WebRTC

  @moduletag :capture_log

  @answer %{"type" => "answer", "sdp" => "v=0\r\n"}
  @ice_candidate %{
    "candidate" => "candidate:1 1 UDP 2122252543 192.168.1.10 51000 typ host",
    "sdpMid" => "0",
    "sdpMLineIndex" => 0
  }

  setup do
    {[], state} = WebRTC.handle_init(%{}, %{ice_servers: []})
    %{state: state}
  end

  describe "messages referencing unknown peers" do
    test "local ice candidate from a removed peer connection is dropped", %{state: state} do
      # The peer connection keeps emitting candidates for a short while after
      # being removed from state (failed connection / channel down). This used
      # to crash with `send(nil, _)`.
      unknown_pc = self()

      candidate = %ExWebRTC.ICECandidate{candidate: "candidate:1", sdp_mid: "0"}

      assert {[], ^state} =
               WebRTC.handle_info(
                 {:ex_webrtc, unknown_pc, {:ice_candidate, candidate}},
                 %{},
                 state
               )
    end

    test "answer for an unknown peer is ignored", %{state: state} do
      assert {[], ^state} =
               WebRTC.handle_parent_notification({:answer, self(), @answer}, %{}, state)
    end

    test "remote ice candidate for an unknown peer is ignored", %{state: state} do
      assert {[], ^state} =
               WebRTC.handle_parent_notification(
                 {:ice_candidate, self(), @ice_candidate},
                 %{},
                 state
               )
    end
  end

  describe "messages referencing a dead peer connection" do
    setup %{state: state} do
      pc = spawn(fn -> :ok end)
      ref = Process.monitor(pc)
      assert_receive {:DOWN, ^ref, :process, ^pc, _reason}

      state = %{
        state
        | peers: Map.put(state.peers, pc, self()),
          peers_state: Map.put(state.peers_state, pc, :connected)
      }

      %{state: state, pc: pc}
    end

    test "answer does not crash the sink", %{state: state} do
      assert {[], ^state} =
               WebRTC.handle_parent_notification({:answer, self(), @answer}, %{}, state)
    end

    test "remote ice candidate does not crash the sink", %{state: state} do
      assert {[], ^state} =
               WebRTC.handle_parent_notification(
                 {:ice_candidate, self(), @ice_candidate},
                 %{},
                 state
               )
    end
  end

  describe "buffers" do
    test "are dropped when there are no peers", %{state: state} do
      buffer = %Membrane.Buffer{payload: <<0, 0, 0, 1>>, pts: 0}

      assert {[], ^state} = WebRTC.handle_buffer(:video, buffer, %{}, state)
    end
  end
end
