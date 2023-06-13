defmodule ExNVRWeb.API.DeviceStreamingController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  require Logger

  alias Ecto.Changeset
  alias ExNVR.Pipelines.HlsPlayback
  alias ExNVR.Utils

  @spec hls_stream(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, Changeset.t()}
  def hls_stream(conn, params) do
    with {:ok, params} <- validate_hls_stream_params(params) do
      path = start_hls_pipeline(conn.assigns.device.id, params.pos)
      manifest_file = File.read!(Path.join(path, "index.m3u8"))
      send_resp(conn, 200, remove_unused_stream(manifest_file, params))
    end
  end

  @spec hls_stream_segment(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, Changeset.t()}
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
    types = %{pos: :utc_datetime, stream: :integer}

    {%{pos: nil, stream: nil}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_inclusion(:stream, [0, 1])
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

  def remove_unused_stream(manifest_file, %{pos: pos}) when not is_nil(pos), do: manifest_file
  def remove_unused_stream(manifest_file, %{stream: nil}), do: manifest_file

  def remove_unused_stream(manifest_file, %{stream: stream}) do
    track_to_delete =
      if stream == 0,
        do: "live_sub_stream",
        else: "live_main_stream"

    manifest_file_lines = String.split(manifest_file, "\n")

    case Enum.find_index(manifest_file_lines, &String.starts_with?(&1, track_to_delete)) do
      nil ->
        manifest_file

      idx ->
        manifest_file_lines
        |> Enum.with_index()
        |> Enum.reject(fn {_, index} -> index in [idx - 1, idx] end)
        |> Enum.map_join("\n", fn {line, _} -> line end)
    end
  end
end
