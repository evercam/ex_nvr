defmodule ExNVR.Pipelines.VideoAssemblerTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @moduletag :tmp_dir

  setup ctx do
    device = camera_device_fixture(ctx.tmp_dir)
    device2 = camera_device_fixture(ctx.tmp_dir)

    dates = [
      {~U(2023-06-23 10:00:00Z), ~U(2023-06-23 10:00:05Z)},
      {~U(2023-06-23 10:00:05Z), ~U(2023-06-23 10:00:10Z)},
      {~U(2023-06-23 10:00:13Z), ~U(2023-06-23 10:00:18Z)}
    ]

    recordings =
      for {start_date, end_date} <- dates do
        recording_fixture(device, start_date: start_date, end_date: end_date)
      end

    hevc_recordings =
      for {start_date, end_date} <- dates do
        recording_fixture(device2, start_date: start_date, end_date: end_date, encoding: :H265)
      end

    {:ok, devices: {device, device2}, recordings: recordings, hevc_recordings: hevc_recordings}
  end

  describe "Assemble video files when" do
    test "providing start date and end date", %{devices: {device, device2}, tmp_dir: tmp_dir} do
      perform_test(device, tmp_dir, ~U(2023-06-23 10:00:15Z), 0)
      perform_test(device2, tmp_dir, ~U(2023-06-23 10:00:15Z), 0)
    end

    test "providing start date and duration", %{devices: {device, device2}, tmp_dir: tmp_dir} do
      perform_test(device, tmp_dir, ~U(2099-01-01 00:00:00Z), Membrane.Time.seconds(10))
      perform_test(device2, tmp_dir, ~U(2099-01-01 00:00:00Z), Membrane.Time.seconds(10))
    end
  end

  defp perform_test(device, tmp_dir, end_date, duration) do
    destination = Path.join(tmp_dir, "output.mp4")

    pid =
      prepare_pipeline(device,
        start_date: ~U(2023-06-23 10:00:03Z),
        end_date: end_date,
        duration: duration,
        destination: destination
      )

    assert_end_of_stream(pid, :sink)
    assert File.exists?(destination)
  end

  defp prepare_pipeline(device, options) do
    options = [
      module: ExNVR.Pipelines.VideoAssembler,
      custom_args: Keyword.merge([device: device], options)
    ]

    Testing.Pipeline.start_supervised!(options)
  end
end
