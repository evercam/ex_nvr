defmodule ExNVR.Elements.CVSBuffererTest do
  @moduledoc false

  use ExUnit.Case

  require Membrane.Pad

  alias ExNVR.Elements.CVSBufferer
  alias Membrane.Pad

  @ctx %{}
  @stream_format %Membrane.H264{width: 1080, height: 720}

  test "Buffer CVS (coded video sequence)" do
    assert {[], state} = CVSBufferer.handle_init(@ctx, nil)

    assert {[], %{stream_format: @stream_format} = state} =
             CVSBufferer.handle_stream_format(:input, @stream_format, @ctx, state)

    {state, buffers} =
      Enum.reduce(1..10, {state, []}, fn idx, {state, buffers} ->
        key_frame? = rem(idx, 4) == 0
        buffer = generate_buffer(key_frame?)

        buffers = if key_frame?, do: [buffer], else: [buffer | buffers]

        assert {[], %{cvs: ^buffers} = state} =
                 CVSBufferer.handle_buffer(:input, buffer, @ctx, state)

        {state, buffers}
      end)

    buffers = Enum.reverse(buffers)
    pad = Pad.ref(:output, make_ref())

    actions =
      [stream_format: {pad, @stream_format}] ++
        Enum.map(buffers, &{:buffer, {pad, &1}}) ++ [end_of_stream: pad]

    assert {^actions, ^state} = CVSBufferer.handle_pad_added(pad, @ctx, state)
  end

  defp generate_buffer(key_frame?) do
    %Membrane.Buffer{
      payload: UUID.uuid4(),
      dts: 0,
      pts: 0,
      metadata: %{
        h264: %{
          key_frame?: key_frame?
        }
      }
    }
  end
end
