defmodule ExNVR.Pipelines.HlsPlaybackTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.{DevicesFixtures, RecordingsFixtures}
  import ExNVR.HLS.Assertions
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

    %{device: device}
  end

  describe "Hls playback" do
    test "playback recording", %{device: device, tmp_dir: out_dir} do
      pid = prepare_pipeline(device, directory: out_dir)

      ExNVR.Pipelines.HlsPlayback.start_streaming(pid)

      assert_pipeline_play(pid)
      assert_pipeline_notified(pid, :sink, {:track_playable, :playback})

      check_hls_playlist(out_dir, 2)

      ExNVR.Pipelines.HlsPlayback.stop_streaming(pid)
    end
  end

  defp prepare_pipeline(device, options) do
    options = [
      module: ExNVR.Pipelines.HlsPlayback,
      custom_args:
        [device_id: device.id, start_date: ~U(2023-06-23 10:00:02Z)] |> Keyword.merge(options)
    ]

    Testing.Pipeline.start_supervised!(options)
  end
end