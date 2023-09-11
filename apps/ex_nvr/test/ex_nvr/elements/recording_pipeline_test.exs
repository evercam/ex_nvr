defmodule ExNVR.Elements.RecordingPipelineTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.{DevicesFixtures, RecordingsFixtures}
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias ExNVR.Elements.RecordingBin

  @moduletag :tmp_dir

  setup do
    device = device_fixture()
    File.mkdir!(ExNVR.Utils.recording_dir(device.id))

    recording_fixture(device,
      start_date: ~U(2023-09-06 10:00:00Z),
      end_date: ~U(2023-09-06 10:00:05Z)
    )

    recording_fixture(device,
      start_date: ~U(2023-09-06 10:00:05Z),
      end_date: ~U(2023-09-06 10:00:10Z)
    )

    recording_fixture(device,
      start_date: ~U(2023-09-06 10:01:15Z),
      end_date: ~U(2023-09-06 10:01:20Z)
    )

    {:ok, device: device}
  end

  describe "Read multiple recordings as one file" do
    test "starting from keyframe before", %{device: device, tmp_dir: tmp_dir} do
      out_path = Path.join(tmp_dir, "output.h264")

      ref_path =
        "../../fixtures/h264/reference-recording-keyframe-before.h264" |> Path.expand(__DIR__)

      perform_test(
        device,
        out_path,
        ref_path,
        ~U(2023-09-06 10:00:03Z),
        ~U(2023-09-06 10:01:16.98Z),
        :keyframe_before
      )
    end

    test "starting from keyframe after", %{device: device, tmp_dir: tmp_dir} do
      out_path = Path.join(tmp_dir, "output.h264")

      ref_path =
        "../../fixtures/h264/reference-recording-keyframe-after.h264" |> Path.expand(__DIR__)

      perform_test(
        device,
        out_path,
        ref_path,
        ~U(2023-09-06 10:00:03Z),
        ~U(2023-09-06 10:01:16.98Z),
        :keyframe_after
      )
    end

    test "starting from exact timestamp", %{device: device, tmp_dir: tmp_dir} do
      out_path = Path.join(tmp_dir, "output.h264")

      ref_path =
        "../../fixtures/h264/reference-recording-exact.h264" |> Path.expand(__DIR__)

      perform_test(
        device,
        out_path,
        ref_path,
        ~U(2023-09-06 10:00:03Z),
        ~U(2023-09-10 10:00:00Z),
        :exact,
        Membrane.Time.milliseconds(8950)
      )
    end
  end

  describe "Read no recordings" do
    test "source notifies parent", %{device: device, tmp_dir: tmp_dir} do
      out_path = Path.join(tmp_dir, "output.h264")

      pid =
        start_pipeline(
          device,
          out_path,
          ~U(2023-09-05 10:00:03Z),
          ~U(2023-09-05 10:01:10Z),
          :keyframe_before,
          0
        )

      assert_pipeline_play(pid)
      assert_pipeline_notified(pid, :source, :no_recordings)

      Membrane.Testing.Pipeline.terminate(pid)
    end
  end

  defp perform_test(device, out_path, ref_path, start_date, end_date, startegy, duration \\ 0) do
    pid = start_pipeline(device, out_path, start_date, end_date, startegy, duration)

    assert_pipeline_play(pid)
    assert_end_of_stream(pid, :sink, :input, 5_000)

    Membrane.Testing.Pipeline.terminate(pid)

    assert File.exists?(out_path)
    assert File.read!(out_path) == File.read!(ref_path), "Content not equal"
  end

  defp start_pipeline(
         device,
         out_file,
         start_date,
         end_date,
         strategy,
         duration
       ) do
    structure = [
      child(:source, %RecordingBin{
        device_id: device.id,
        start_date: start_date,
        end_date: end_date,
        strategy: strategy,
        duration: duration
      })
      |> via_out(:video)
      # |> child(:filer, %Membrane.Debug.Filter{handle_buffer: &IO.inspect/1})
      |> child(:sink, %Membrane.File.Sink{location: out_file})
    ]

    Membrane.Testing.Pipeline.start_link_supervised!(structure: structure)
  end
end
