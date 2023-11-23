defmodule ExNVR.Pipelines.VideoAssemblerTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures
  import Membrane.Testing.Assertions

  alias ExNVR.Model.Recording
  alias Membrane.Testing

  @moduletag :tmp_dir

  setup ctx do
    device = device_fixture(%{settings: %{storage_address: ctx.tmp_dir}})

    recording1 =
      recording_fixture(device,
        start_date: ~U(2023-06-23 10:00:00Z),
        end_date: ~U(2023-06-23 10:00:05Z)
      )

    recording2 =
      recording_fixture(device,
        start_date: ~U(2023-06-23 10:00:05Z),
        end_date: ~U(2023-06-23 10:00:10Z)
      )

    recording3 =
      recording_fixture(device,
        start_date: ~U(2023-06-23 10:00:13Z),
        end_date: ~U(2023-06-23 10:00:18Z)
      )

    {:ok, device: device, recordings: [recording1, recording2, recording3]}
  end

  describe "Assemble video files when" do
    test "providing start date and end date", %{device: device, tmp_dir: tmp_dir} do
      destination = Path.join(tmp_dir, "output.mp4")

      pid =
        prepare_pipeline(device,
          start_date: ~U(2023-06-23 10:00:02Z),
          end_date: ~U(2023-06-23 10:00:15Z),
          destination: destination
        )

      assert_pipeline_play(pid)
      assert_end_of_stream(pid, :sink)
      assert File.exists?(destination)
    end

    test "providing start date and duration", %{device: device, tmp_dir: tmp_dir} do
      destination = Path.join(tmp_dir, "output.mp4")

      pid =
        prepare_pipeline(device,
          start_date: ~U(2023-06-23 10:00:03Z),
          duration: Membrane.Time.seconds(10),
          destination: destination
        )

      assert_pipeline_play(pid)
      assert_end_of_stream(pid, :sink)
      assert File.exists?(destination)
    end

    test "using native assembler", %{device: device, recordings: recordings, tmp_dir: tmp_dir} do
      rec =
        Enum.map(
          recordings,
          &Recording.Download.new(&1, ExNVR.Recordings.recording_path(device, &1))
        )

      start_date = DateTime.to_unix(~U(2023-06-23 10:00:03Z), :millisecond)
      end_date = DateTime.to_unix(~U(2023-06-23 10:00:15Z), :millisecond)
      destination = Path.join(tmp_dir, "output.mp4")

      assert {:ok, real_start_date} =
               ExNVR.Recordings.VideoAssembler.Native.assemble_recordings(
                 rec,
                 start_date,
                 end_date,
                 0,
                 destination
               )

      assert File.exists?(destination)
      assert_in_delta(real_start_date, start_date, 1100)
    end
  end

  defp prepare_pipeline(device, options) do
    options = [
      module: ExNVR.Pipelines.VideoAssembler,
      custom_args: Keyword.merge([device: device], options)
    ]

    Testing.Pipeline.start_supervised!(options)
  end
end
