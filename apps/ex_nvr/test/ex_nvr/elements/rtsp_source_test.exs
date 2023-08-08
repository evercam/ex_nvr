defmodule ExNVR.Elements.RTSP.SourceTest do
  @moduledoc false

  use ExUnit.Case

  require Membrane.Pad

  alias Membrane.RemoteStream
  alias ExNVR.Elements.RTSP.Source
  alias ExNVR.MediaTrack
  alias Membrane.Pad

  @rtsp_uri "rtsp://example.com:554/video1"
  @packet <<1::128>>

  test "connection manager process started and alive" do
    state = init_source()
    assert {[], state} = Source.handle_setup(%{}, state)

    assert is_pid(state.connection_manager)
    assert Process.alive?(state.connection_manager)
  end

  test "rtsp setup complete message received" do
    state = init_source()
    assert {[], _} = Source.handle_setup(%{}, state)

    assert_receive {:rtsp_setup_complete,
                    %MediaTrack{type: :video, clock_rate: 90_000, payload_type: 96}},
                   1_000
  end

  test "media packets message are buffered" do
    state = init_source()
    assert {[], state} = Source.handle_setup(%{}, state)

    output_pad = Pad.ref(:output, state.output_ref)

    assert {[], state} = Source.handle_info({:media_packet, @packet}, %{}, state)
    assert {[], state} = Source.handle_info({:media_packet, @packet}, %{}, state)
    assert {[], state} = Source.handle_info({:media_packet, @packet}, %{}, state)

    assert [
             {:buffer, {^output_pad, %{payload: @packet}}},
             {:buffer, {^output_pad, %{payload: @packet}}},
             {:buffer, {^output_pad, %{payload: @packet}}}
           ] = state.buffered_actions
  end

  test "stream format and buffered packets are sent when pad is connected" do
    state = init_source()
    assert {[], state} = Source.handle_setup(%{}, state)

    output_pad = Pad.ref(:output, state.output_ref)

    assert {[], state} = Source.handle_info({:media_packet, @packet}, %{}, state)
    assert {[], state} = Source.handle_info({:media_packet, @packet}, %{}, state)

    assert {[
              {:stream_format, {^output_pad, %RemoteStream{type: :packetized}}},
              {:buffer, {^output_pad, %{payload: @packet}}},
              {:buffer, {^output_pad, %{payload: @packet}}}
            ], %{play?: true} = state} = Source.handle_pad_added(output_pad, %{}, state)

    assert {[{:buffer, {^output_pad, %{payload: @packet}}}], _state} =
             Source.handle_info({:media_packet, @packet}, %{}, state)
  end

  defp init_source() do
    assert {[],
            %{
              stream_uri: @rtsp_uri,
              connection_manager: nil,
              play?: false,
              buffered_actions: []
            } = state} = Source.handle_init(%{}, %Source{stream_uri: @rtsp_uri})

    state
  end
end
