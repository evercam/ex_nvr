defmodule ExNVRWeb.API.DeviceStreamingController do
  @moduledoc false

  use ExNVRWeb, :controller

  require Logger

  alias Ecto.Changeset
  alias ExNVR.Pipelines.HlsPlayback
  alias ExNVR.Utils

  def hls_stream(conn, params) do
    with {:ok, params} <- validate_hls_stream_params(params) do
      path = start_hls_pipeline(conn.assigns.device.id, params.pos)
      send_file(conn, 200, Path.join(path, "index.m3u8"))
    end
  end

  def hls_stream_segment(conn, %{"segment_name" => segment_name}) do
    # segment names are in the following format <segment_name>_<track_id>_<segment_id>.<extension>
    # this is a temporary measure until Membrane HLS plugin supports query params
    # in segment files
    id =
      segment_name
      |> Path.basename(".m3u8")
      |> String.trim_leading("video_header_")
      |> String.split("_")
      |> hd()

    if not String.ends_with?(segment_name, ".m3u8") do
      ExNVRWeb.HlsStreamingMonitor.update_last_access_time(id)
    end

    send_file(conn, 200, Path.join([Utils.hls_dir(conn.assigns.device.id), id, segment_name]))
  end

  defp validate_hls_stream_params(params) do
    types = %{pos: :utc_datetime}

    {%{pos: nil}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.apply_action(:create)
  end

  defp start_hls_pipeline(device_id, nil) do
    Path.join(Utils.hls_dir(device_id), "live")
  end

  defp start_hls_pipeline(device_id, pos) do
    id = UUID.uuid4()

    path =
      device_id
      |> Utils.hls_dir()
      |> Path.join(id)

    pipeline_options = [
      device_id: device_id,
      start_date: pos,
      directory: path,
      segment_name_prefix: id
    ]

    {:ok, _, pid} = HlsPlayback.start(pipeline_options)
    ExNVRWeb.HlsStreamingMonitor.register(id, fn -> HlsPlayback.stop_streaming(pid) end)

    :ok = HlsPlayback.start_streaming(pid)

    path
  end
end
