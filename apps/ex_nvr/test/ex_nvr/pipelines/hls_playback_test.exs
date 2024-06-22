defmodule ExNVR.Pipelines.HlsPlaybackTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.{DevicesFixtures, RecordingsFixtures}
  import ExNVR.HLS.Assertions
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @moduletag :tmp_dir

  setup ctx do
    device = camera_device_fixture(ctx.tmp_dir)

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
      pid = prepare_pipeline(device, directory: out_dir, stream: :high)

      ExNVR.Pipelines.HlsPlayback.start_streaming(pid)

      assert_pipeline_notified(pid, :sink, {:track_playable, :playback})

      check_hls_playlist(out_dir, 2)

      ExNVR.Pipelines.HlsPlayback.stop_streaming(pid)
    end
  end

  defp prepare_pipeline(device, options) do
    options = [
      module: ExNVR.Pipelines.HlsPlayback,
      custom_args:
        [device: device, start_date: ~U(2023-06-23 10:00:02Z), duration: 0]
        |> Keyword.merge(options)
    ]

    Testing.Pipeline.start_supervised!(options)
  end
end
