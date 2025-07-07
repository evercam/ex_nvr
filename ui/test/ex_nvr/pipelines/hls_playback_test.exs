defmodule ExNVR.Pipelines.HlsPlaybackTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.{DevicesFixtures, RecordingsFixtures}
  import ExNVR.HLS.Assertions
  import Membrane.Testing.Assertions

  alias ExNVR.Pipelines.HlsPlayback
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

    %{device: device, hls_dir: Path.join(ctx.tmp_dir, UUID.uuid4())}
  end

  describe "Hls playback" do
    test "playback recording", %{device: device, hls_dir: dir} do
      pid = prepare_pipeline(device, directory: dir, stream: :high)

      HlsPlayback.start_streaming(pid)

      assert_pipeline_notified(pid, :sink, {:track_playable, :main_stream})

      check_hls_playlist(dir, 2)

      HlsPlayback.stop_streaming(pid)
    end

    test "playback recording with transcoding", %{device: device, hls_dir: dir} do
      pid = prepare_pipeline(device, directory: dir, stream: :high, resolution: 240)

      HlsPlayback.start_streaming(pid)

      assert_pipeline_notified(pid, :sink, {:track_playable, :main_stream})

      check_hls_playlist(dir, 2)

      HlsPlayback.stop_streaming(pid)
    end
  end

  defp prepare_pipeline(device, options) do
    options = [
      module: HlsPlayback,
      custom_args:
        [device: device, start_date: ~U(2023-06-23 10:00:02Z), duration: 0]
        |> Keyword.merge(options)
    ]

    Testing.Pipeline.start_supervised!(options)
  end
end
