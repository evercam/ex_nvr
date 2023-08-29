defmodule ExNVR.Pipeline.Output.Bif.KeyFrameSelectorTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.Pipeline.Output.Bif.KeyFrameSelector
  alias Membrane.{Buffer, Time}

  test "Select key frames" do
    assert {[], state} =
             KeyFrameSelector.handle_init(%{}, %KeyFrameSelector{
               interval: Time.seconds(1)
             })

    buffer = generate_buffer(200)

    assert {[buffer: {:output, ^buffer}], %{last_keyframe_pts: pts} = state} =
             KeyFrameSelector.handle_process(:input, buffer, %{}, state)

    assert pts == Time.milliseconds(200)

    assert {[], %{last_keyframe_pts: ^pts} = state} =
             KeyFrameSelector.handle_process(:input, generate_buffer(500, false), %{}, state)

    assert {[], %{last_keyframe_pts: ^pts} = state} =
             KeyFrameSelector.handle_process(:input, generate_buffer(1300, false), %{}, state)

    buffer = generate_buffer(1500)

    assert {[buffer: {:output, ^buffer}], %{last_keyframe_pts: pts}} =
             KeyFrameSelector.handle_process(:input, buffer, %{}, state)

    assert pts == Time.milliseconds(1500)
  end

  defp generate_buffer(pts_in_ms, key_frame? \\ true) do
    %Buffer{
      payload: String.duplicate(<<1>>, 10),
      pts: Time.milliseconds(pts_in_ms),
      metadata: %{
        h264: %{
          key_frame?: key_frame?
        }
      }
    }
  end
end
