defmodule ExNVR.Recordings.VideoAssembler do
  @moduledoc """
  Assemble videos segments (chunks) into one file.
  """

  alias ExMP4.Writer
  alias ExNVR.Recordings.Concatenater

  @video_timescale 90_000

  @spec assemble(
          ExNVR.Model.Device.t(),
          ExNVR.Recordings.stream_type(),
          DateTime.t(),
          DateTime.t(),
          non_neg_integer(),
          Path.t()
        ) :: DateTime.t()
  def assemble(device, stream, start_date, end_date, duration, dest) do
    {:ok, offset, cat} = Concatenater.new(device, stream, start_date, annexb: false)
    [track] = Concatenater.tracks(cat)
    duration = ExMP4.Helper.timescalify(duration, :second, @video_timescale)

    writer =
      Writer.new!(dest)
      |> Writer.add_track(%{track | timescale: @video_timescale})
      |> Writer.write_header()

    acc = %{
      cat: cat,
      track: track,
      end_date: end_date,
      duration: duration
    }

    :ok =
      Stream.resource(
        fn -> acc end,
        &next_sample/1,
        &Concatenater.close(&1.cat)
      )
      |> Enum.to_list()
      |> Enum.into(writer)
      |> Writer.write_trailer()

    DateTime.add(cat.start_date, -offset, :millisecond)
  end

  defp next_sample(acc) do
    with {:ok, {sample, timestamp}, cat} <- Concatenater.next_sample(acc.cat, acc.track.id),
         true <- sample.dts < acc.duration,
         true <- DateTime.compare(timestamp, acc.end_date) == :lt do
      {[sample], %{acc | cat: cat}}
    else
      _other -> {:halt, acc}
    end
  end
end
