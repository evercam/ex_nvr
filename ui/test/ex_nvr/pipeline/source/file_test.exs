defmodule ExNVR.Pipeline.Source.FileTest do
  @moduledoc false

  use ExNVR.DataCase, async: true

  import ExNVR.DevicesFixtures

  alias ExNVR.Pipeline.Source

  @ctx %{}

  setup do
    %{device: file_device_fixture()}
  end

  test "init file source", %{device: device} do
    assert {[], state} = Source.File.handle_init(@ctx, %Source.File{device: device})
    assert map_size(state.tracks) == 1

    assert {[notify_parent: {:main_stream, track_id, media_track}], _state} =
             Source.File.handle_setup(@ctx, state)

    assert track_id == 1
    assert %ExNVR.Pipeline.Track{encoding: :H264, type: :video} = media_track
  end

  test "read sample", %{device: device} do
    assert {[], state} = Source.File.handle_init(@ctx, %Source.File{device: device})

    assert {[buffer: {nil, buffer}], state} =
             Source.File.handle_info({:send_frame, 1}, @ctx, state)

    assert %Membrane.Buffer{dts: 0, pts: 0, payload: <<0, 0, 0, 1, _data::binary>>} = buffer

    assert_receive {:send_frame, 1}, 1_000, "send_frame message not received"

    assert {[terminate: :normal], _state} = Source.File.handle_terminate_request(@ctx, state)
  end
end
