defmodule ExNVR.Pipeline.Output.ThumbnailerPipelineTest do
  @moduledoc false

  use ExNVR.DataCase

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing.Pipeline

  @h264_fixture "../../../../fixtures/video-30-10s.h264" |> Path.expand(__DIR__)
  @h265_fixture "../../../../fixtures/video-30-10s.h265" |> Path.expand(__DIR__)

  @moduletag :tmp_dir

  test "thumbnail h264 video", %{tmp_dir: tmp_dir} do
    perform_test(@h264_fixture, tmp_dir, :H264)
  end

  test "thumbnail h265 video", %{tmp_dir: tmp_dir} do
    perform_test(@h265_fixture, tmp_dir, :H265)
  end

  defp perform_test(file, dest, encoding) do
    spec = [
      child(:source, %Membrane.File.Source{location: file})
      |> child(:parser, get_parser(encoding))
      |> child(:thumbnailer, %ExNVR.Pipeline.Output.Thumbnailer{
        interval: Membrane.Time.seconds(2),
        encoding: encoding,
        dest: dest
      })
    ]

    pid = Pipeline.start_supervised!(spec: spec)

    assert_end_of_stream(pid, :parser)
    assert_pipeline_notified(pid, :thumbnailer, :end_of_stream)
    Pipeline.terminate(pid)

    assert length(File.ls!(dest)) == 5
  end

  defp get_parser(:H264),
    do: %Membrane.H264.Parser{
      output_stream_structure: :annexb,
      generate_best_effort_timestamps: %{framerate: {30, 1}}
    }

  defp get_parser(:H265),
    do: %Membrane.H265.Parser{
      output_stream_structure: :annexb,
      generate_best_effort_timestamps: %{framerate: {30, 1}}
    }
end
