defmodule ExNVR.Pipeline.Source.RTSP.SourceTest do
  @moduledoc false

  use ExUnit.Case

  require Membrane.Pad

  alias ExNVR.Pipeline.Source.RTSP.Source
  alias Membrane.{Pad, RemoteStream}

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

    assert_receive {:rtsp_setup_complete, tracks}, 1_000

    assert length(tracks) == 2
    assert Enum.map(tracks, & &1.type) |> Enum.sort() == [:application, :video]
  end

  test "media packets message are buffered" do
    state = init_source()
    assert {[], state} = Source.handle_setup(%{}, state)

    assert {[], state} = Source.handle_info({:media_packet, 0, @packet}, %{}, state)
    assert {[], state} = Source.handle_info({:media_packet, 0, @packet}, %{}, state)
    assert {[], state} = Source.handle_info({:media_packet, 0, @packet}, %{}, state)

    assert [%{payload: @packet}, %{payload: @packet}, %{payload: @packet}] = state.buffers
  end

  test "stream format and buffered packets are sent when pad is connected" do
    state = init_source()
    assert {[], state} = Source.handle_setup(%{}, state)

    output_pad = Pad.ref(:output, make_ref())

    assert {[], state} = Source.handle_info({:media_packet, 0, @packet}, %{}, state)
    assert {[], state} = Source.handle_info({:media_packet, 0, @packet}, %{}, state)

    assert {[
              {:stream_format, {^output_pad, %RemoteStream{type: :packetized}}},
              {:buffer, {^output_pad, %{payload: @packet}}},
              {:buffer, {^output_pad, %{payload: @packet}}}
            ], %{play?: true} = state} = Source.handle_pad_added(output_pad, %{}, state)

    assert {[{:buffer, {^output_pad, %{payload: @packet}}}], _state} =
             Source.handle_info({:media_packet, 0, @packet}, %{}, state)
  end

  defp init_source() do
    assert {[],
            %{
              stream_uri: @rtsp_uri,
              connection_manager: nil,
              play?: false,
              buffers: []
            } = state} = Source.handle_init(%{}, %Source{stream_uri: @rtsp_uri})

    state
  end
end
