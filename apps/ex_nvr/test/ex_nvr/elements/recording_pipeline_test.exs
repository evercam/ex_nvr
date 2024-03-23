defmodule ExNVR.Elements.RecordingPipelineTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.{DevicesFixtures, RecordingsFixtures}
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias ExNVR.Elements.RecordingBin
  alias Membrane.{H264, H265}
  alias Membrane.Testing.Pipeline

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, device: camera_device_fixture(tmp_dir)}
  end

  describe "Read multiple avc1 recordings as one file" do
    setup %{device: device} do
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

      :ok
    end

    test "starting from keyframe before", %{device: device, tmp_dir: tmp_dir} do
      out_path = Path.join(tmp_dir, "output.h264")

      ref_path =
        "../../fixtures/h264/reference-recording-keyframe-before.h264" |> Path.expand(__DIR__)

      source_params = %{
        device: device,
        start_date: ~U(2023-09-06 10:00:03Z),
        end_date: ~U(2023-09-06 10:01:16.98Z),
        strategy: :keyframe_before
      }

      perform_test(:H264, out_path, ref_path, source_params)
    end

    test "starting from keyframe after", %{device: device, tmp_dir: tmp_dir} do
      out_path = Path.join(tmp_dir, "output.h264")

      ref_path =
        "../../fixtures/h264/reference-recording-keyframe-after.h264" |> Path.expand(__DIR__)

      source_params = %{
        device: device,
        start_date: ~U(2023-09-06 10:00:03Z),
        end_date: ~U(2023-09-06 10:01:16.98Z),
        strategy: :keyframe_after
      }

      perform_test(:H264, out_path, ref_path, source_params)
    end

    test "starting from exact timestamp", %{device: device, tmp_dir: tmp_dir} do
      out_path = Path.join(tmp_dir, "output.h264")

      ref_path =
        "../../fixtures/h264/reference-recording-exact.h264" |> Path.expand(__DIR__)

      source_params = %{
        device: device,
        start_date: ~U(2023-09-06 10:00:03.001Z),
        end_date: ~U(2023-09-10 10:00:00Z),
        duration: Membrane.Time.milliseconds(8950),
        strategy: :exact
      }

      perform_test(:H264, out_path, ref_path, source_params)
    end
  end

  describe "Read multiple hvc1 recordings as one file" do
    setup %{device: device} do
      recording_fixture(device,
        start_date: ~U(2023-09-06 10:00:00Z),
        end_date: ~U(2023-09-06 10:00:05Z),
        encoding: :H265
      )

      recording_fixture(device,
        start_date: ~U(2023-09-06 10:00:05Z),
        end_date: ~U(2023-09-06 10:00:10Z),
        encoding: :H265
      )

      recording_fixture(device,
        start_date: ~U(2023-09-06 10:01:15Z),
        end_date: ~U(2023-09-06 10:01:20Z),
        encoding: :H265
      )

      :ok
    end

    test "starting from keyframe before", %{device: device, tmp_dir: tmp_dir} do
      out_path = Path.join(tmp_dir, "output.h265")
      ref_path = "../../fixtures/h265/ref-recording-keyframe-before.h265" |> Path.expand(__DIR__)

      source_params = %{
        device: device,
        start_date: ~U(2023-09-06 10:00:03Z),
        end_date: ~U(2023-09-06 10:01:16.98Z),
        strategy: :keyframe_before
      }

      perform_test(:H265, out_path, ref_path, source_params)
    end

    test "starting from keyframe after", %{device: device, tmp_dir: tmp_dir} do
      out_path = Path.join(tmp_dir, "output.h265")
      ref_path = "../../fixtures/h265/ref-recording-keyframe-after.h265" |> Path.expand(__DIR__)

      source_params = %{
        device: device,
        start_date: ~U(2023-09-06 10:00:03Z),
        end_date: ~U(2023-09-06 10:01:16.98Z),
        strategy: :keyframe_after
      }

      perform_test(:H265, out_path, ref_path, source_params)
    end
  end

  describe "Read no recordings" do
    test "source notifies parent", %{device: device} do
      params = %{
        device: device,
        start_date: ~U(2023-09-05 10:00:03Z)
      }

      pid =
        Membrane.Testing.Pipeline.start_link_supervised!(
          spec: [child(:source, struct(RecordingBin, params))]
        )

      assert_pipeline_notified(pid, :source, :no_recordings)

      Membrane.Testing.Pipeline.terminate(pid)
    end
  end

  defp perform_test(encoding, out_path, ref_path, source_params) do
    pid =
      Membrane.Testing.Pipeline.start_link_supervised!(
        spec: [child(:source, struct(RecordingBin, source_params))]
      )

    assert_pipeline_notified(pid, :source, {:track, %module{}})

    case encoding do
      :H264 -> assert module == H264
      :H265 -> assert module == H265
    end

    Pipeline.execute_actions(pid,
      spec: [
        get_child(:source)
        |> via_out(:video)
        |> child(:sink, %Membrane.File.Sink{location: out_path})
      ]
    )

    assert_end_of_stream(pid, :sink, :input, 5_000)
    Pipeline.terminate(pid)

    assert File.exists?(out_path)
    assert File.read!(out_path) == File.read!(ref_path)
  end
end
