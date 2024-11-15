defmodule ExNVR.Elements.Recording.ScissorsTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.Elements.Recording.Scissors
  alias Membrane.{Buffer, Time}

  @date ~U(2023-09-06 10:00:00Z)
  @buffers for i <- 0..9,
               do: %Buffer{
                 pts: Time.seconds(i),
                 dts: Time.seconds(i),
                 payload: <<i::8>>,
                 metadata: %{
                   timestamp: Time.from_datetime(@date) + Time.seconds(i),
                   h264: %{key_frame?: rem(i, 4) == 0}
                 }
               }

  describe "Start stream" do
    test "from exact timestamp" do
      state = init_scissors(~U(2023-09-06 10:00:02Z), :exact)
      perform_test(state, 2..-1)
    end

    test "from closest keyframe before start date" do
      state = init_scissors(~U(2023-09-06 10:00:06Z), :keyframe_before)
      perform_test(state, 4..-1)
    end

    test "from closest keyframe after start date" do
      state = init_scissors(~U(2023-09-06 10:00:06Z), :keyframe_after)
      perform_test(state, 8..-1)
    end
  end

  describe "End stream" do
    test "when end date is reached" do
      state = init_scissors(~U(2023-09-06 10:00:02Z), :exact, ~U(2023-09-06 10:00:06Z))
      perform_test(state, 2..5)
    end

    test "when duration is reached" do
      state =
        init_scissors(
          ~U(2023-09-06 10:00:06Z),
          :keyframe_before,
          ~U(2099-01-01 00:00:00Z),
          Time.seconds(3)
        )

      perform_test(state, 4..8)
    end
  end

  defp init_scissors(start_date, strategy, end_date \\ ~U(2099-01-01 00:00:00Z), duration \\ 0) do
    assert {[], state} =
             Scissors.handle_init(%{}, %Scissors{
               start_date: Time.from_datetime(start_date),
               strategy: strategy,
               end_date: Time.from_datetime(end_date),
               duration: duration
             })

    state
  end

  defp perform_test(state, range) do
    {expected_buffers, _state} =
      @buffers
      |> Enum.reduce({[], state}, fn buffer, {expected_buffers, state} ->
        case Scissors.handle_buffer(:input, buffer, %{}, state) do
          {[buffer: {:output, buffer}], state} ->
            {expected_buffers ++ List.wrap(buffer), state}

          {_actions, state} ->
            {expected_buffers, state}
        end
      end)

    assert expected_buffers == Enum.slice(@buffers, range)
  end
end
