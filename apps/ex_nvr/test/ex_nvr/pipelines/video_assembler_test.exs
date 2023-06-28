defmodule ExNVR.Pipelines.VideoAssemblerTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @moduletag :tmp_dir

  setup do
    device = device_fixture()

    File.mkdir!(ExNVR.Utils.recording_dir(device.id))

    recording_fixture(device,
      start_date: ~U(2023-06-23 10:00:00Z),
      end_date: ~U(2023-06-23 10:00:05Z)
    )

    recording_fixture(device,
      start_date: ~U(2023-06-23 10:00:05Z),
      end_date: ~U(2023-06-23 10:00:10Z)
    )

    recording_fixture(device,
      start_date: ~U(2023-06-23 10:00:13Z),
      end_date: ~U(2023-06-23 10:00:18Z)
    )

    {:ok, device: device}
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
          duration: Membrane.Time.seconds(60),
          destination: destination
        )

      assert_pipeline_play(pid)
      assert_end_of_stream(pid, :sink)
      assert File.exists?(destination)
    end
  end

  defp prepare_pipeline(device, options) do
    options = [
      module: ExNVR.Pipelines.VideoAssembler,
      custom_args:
        [device_id: device.id]
        |> Keyword.merge(options)
    ]

    Testing.Pipeline.start_supervised!(options)
  end
end
