defmodule ExNVR.Pipelines.MainSubStreamStorageTest do
  use ExNVR.DataCase

  import ExNVR.DevicesFixtures

  alias ExNVR.Pipeline.Track
  alias ExNVR.Pipelines.Main
  alias ExNVR.Pipelines.Main.State

  @ctx %{}

  @moduletag :tmp_dir

  setup do
    %{track: %Track{type: :video, encoding: :h264}}
  end

  defp sub_stream_storage_attached?(device, recording, track) do
    state = %State{device: device, record_main_stream?: recording}

    {actions, _state} =
      Main.handle_child_notification({:sub_stream, %{1 => track}}, :sub_stream, @ctx, state)

    actions
    |> Keyword.get(:spec, [])
    |> inspect(limit: :infinity)
    |> String.contains?("{:storage, :sub_stream}")
  end

  test "attaches sub-stream storage when configured and recording", %{track: track} do
    device = camera_device_fixture("/tmp", %{storage_config: %{record_sub_stream: :always}})

    assert sub_stream_storage_attached?(device, true, track)
  end

  test "does not attach sub-stream storage while not recording", %{track: track} do
    device = camera_device_fixture("/tmp", %{storage_config: %{record_sub_stream: :always}})

    refute sub_stream_storage_attached?(device, false, track)
  end

  test "does not attach sub-stream storage when sub-stream recording is disabled", %{track: track} do
    device = camera_device_fixture("/tmp", %{storage_config: %{record_sub_stream: :never}})

    refute sub_stream_storage_attached?(device, true, track)
  end
end
