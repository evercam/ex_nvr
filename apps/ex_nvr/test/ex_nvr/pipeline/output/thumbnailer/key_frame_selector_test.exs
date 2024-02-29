defmodule ExNVR.Pipeline.Output.Thumbnailer.KeyFrameSelectorTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.Pipeline.Output.Thumbnailer.KeyFrameSelector
  alias Membrane.{Buffer, Time}

  test "Select key frames" do
    assert {[], state} =
             KeyFrameSelector.handle_init(%{}, %KeyFrameSelector{
               interval: Time.seconds(2)
             })

    buffer = generate_buffer(1200)

    assert {[buffer: {:output, ^buffer}], %{last_keyframe_pts: 1} = state} =
             KeyFrameSelector.handle_buffer(:input, buffer, %{}, state)

    assert {[], %{last_keyframe_pts: 1} = state} =
             KeyFrameSelector.handle_buffer(:input, generate_buffer(2500, false), %{}, state)

    assert {[], %{last_keyframe_pts: 1} = state} =
             KeyFrameSelector.handle_buffer(:input, generate_buffer(3300, false), %{}, state)

    buffer = generate_buffer(4800)

    assert {[buffer: {:output, ^buffer}], %{last_keyframe_pts: 5}} =
             KeyFrameSelector.handle_buffer(:input, buffer, %{}, state)
  end

  defp generate_buffer(pts_in_ms, key_frame? \\ true) do
    %Buffer{
      payload: String.duplicate(<<1>>, 10),
      pts: Time.milliseconds(pts_in_ms),
      metadata: %{h264: %{key_frame?: key_frame?}}
    }
  end
end
