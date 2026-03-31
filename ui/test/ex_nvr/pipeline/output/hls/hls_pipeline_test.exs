defmodule ExNVR.Pipeline.Output.HLSPipelineTest do
  @moduledoc false
  use ExUnit.Case, async: true

  require Membrane.Pad

  import ExNVR.HLS.Assertions
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @moduletag :tmp_dir
  @in_file "../../../../fixtures/video-30-10s.h264" |> Path.expand(__DIR__)

  defp start_pipeline(in_file, out_dir, nb_streams \\ 1) do
    spec = [
      child(:source, %Membrane.File.Source{location: in_file})
      |> child(:parser, %Membrane.H264.Parser{
        generate_best_effort_timestamps: %{framerate: {30, 1}}
      })
      |> via_in(:video)
      |> child(:sink, %ExNVR.Pipeline.Output.HLS{
        location: out_dir
      })
    ]

    spec =
      if nb_streams > 1 do
        spec ++
          [
            child(:source2, %Membrane.File.Source{location: in_file})
            |> child(:parser2, %Membrane.H264.Parser{
              generate_best_effort_timestamps: %{framerate: {30, 1}}
            })
            |> via_in(:video)
            |> child({:sink, :sub_stream}, %ExNVR.Pipeline.Output.HLS{
              location: out_dir
            })
          ]
      else
        spec
      end

    Testing.Pipeline.start_link_supervised!(spec: spec)
  end

  describe "hls output element" do
    test "creates hls stream from single (h264) stream", %{tmp_dir: out_dir} do
      pid = start_pipeline(@in_file, out_dir)

      assert_pipeline_notified(pid, :sink, {:track_playable, nil})
      assert_end_of_stream(pid, :parser)

      check_hls_playlist(out_dir, 2)

      Testing.Pipeline.terminate(pid)
    end

    test "creates hls stream from two (h264) streams", %{tmp_dir: out_dir} do
      pid = start_pipeline(@in_file, out_dir, 2)

      assert_pipeline_notified(pid, :sink, {:track_playable, nil})
      assert_pipeline_notified(pid, {:sink, :sub_stream}, {:track_playable, nil})

      assert_end_of_stream(pid, :parser)
      assert_end_of_stream(pid, :parser2)

      check_hls_playlist(out_dir, 2)

      Testing.Pipeline.terminate(pid)
    end
  end
end
