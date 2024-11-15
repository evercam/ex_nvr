defmodule ExNVR.Elements.Recording.TimestamperTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.Elements.Recording.Timestamper

  test "Update dts/pts and add timestamp to buffers" do
    start_date = Membrane.Time.from_datetime(~U(2023-09-05 20:00:00Z))

    assert {[], state} =
             Timestamper.handle_init(%{}, %Timestamper{
               offset: Membrane.Time.seconds(10),
               start_date: start_date
             })

    buffers =
      Enum.map(
        0..9,
        &%Membrane.Buffer{
          payload: <<>>,
          pts: Membrane.Time.seconds(&1),
          dts: Membrane.Time.seconds(&1)
        }
      )

    expected_buffers =
      Enum.map(
        0..9,
        &%Membrane.Buffer{
          payload: <<>>,
          pts: Membrane.Time.seconds(&1 + 10),
          dts: Membrane.Time.seconds(&1 + 10),
          metadata: %{
            timestamp: start_date + Membrane.Time.seconds(&1)
          }
        }
      )

    Enum.reduce(Enum.zip(buffers, expected_buffers), state, fn {buffer, expected_buffer}, state ->
      assert {[buffer: {:output, ^expected_buffer}], state} =
               Timestamper.handle_buffer(:input, buffer, %{}, state)

      state
    end)
  end
end
