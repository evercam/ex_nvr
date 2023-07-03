defmodule ExNVRWeb.API.DeviceStreamingController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  require Logger

  alias Ecto.Changeset
  alias ExNVR.Pipelines.{HlsPlayback, Main, Snapshot, VideoAssembler}
  alias ExNVR.Utils

  @type return_t :: Plug.Conn.t() | {:error, Changeset.t()}

  @spec hls_stream(Plug.Conn.t(), map()) :: return_t()
  def hls_stream(conn, params) do
    with {:ok, params} <- validate_hls_stream_params(params) do
      path = start_hls_pipeline(conn.assigns.device.id, params.pos)
      manifest_file = File.read!(Path.join(path, "index.m3u8"))

      conn
      |> put_resp_content_type("application/vnd.apple.mpegurl")
      |> send_resp(200, remove_unused_stream(manifest_file, params))
    end
  end

  @spec hls_stream_segment(Plug.Conn.t(), map()) :: return_t()
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

  @spec snapshot(Plug.Conn.t(), map()) :: return_t()
  def snapshot(conn, params) do
    with {:ok, params} <- validate_snapshot_req_params(params) do
      if params.time do
        serve_snapshot_from_recorded_videos(conn, params)
      else
        serve_live_snapshot(conn, params)
      end
    end
  end

  @spec footage(Plug.Conn.t(), map()) :: return_t()
  def footage(conn, params) do
    device = conn.assigns.device
    destination = Path.join(System.tmp_dir!(), UUID.uuid4() <> ".mp4")

    with {:ok, params} <- validate_footage_req_params(params) do
      {:ok, pipeline_sup, _pipeline_pid} =
        params
        |> Map.merge(%{device_id: device.id, destination: destination})
        |> Map.update(:duration, 0, &Membrane.Time.seconds/1)
        |> Keyword.new()
        |> VideoAssembler.start()

      Process.monitor(pipeline_sup)

      receive do
        {:DOWN, _ref, :process, ^pipeline_sup, _reason} ->
          send_download(conn, {:file, destination},
            content_type: "video/mp4",
            filename: "#{device.id}.mp4"
          )
      after
        30_000 -> {:error, :not_found}
      end
    end
  end

  defp serve_live_snapshot(conn, params) do
    device = conn.assigns.device

    case device.state do
      :recording ->
        {:ok, snapshot} = Main.live_snapshot(device, params.format)

        conn
        |> put_resp_content_type("image/#{params.format}")
        |> send_resp(:ok, snapshot)

      _ ->
        {:error, :not_found}
    end
  end

  defp serve_snapshot_from_recorded_videos(conn, params) do
    device = conn.assigns.device

    case ExNVR.Recordings.get_recordings_between(device.id, params.time, params.time) do
      [] ->
        {:error, :not_found}

      _ ->
        options = [
          device_id: device.id,
          date: params.time,
          method: params.method,
          format: params.format
        ]

        Snapshot.start_link(options)

        receive do
          {:snapshot, snapshot} ->
            conn
            |> put_resp_content_type("image/#{params.format}")
            |> send_resp(:ok, snapshot)
        after
          10_000 -> {:error, :not_found}
        end
    end
  end

  defp validate_hls_stream_params(params) do
    types = %{pos: :utc_datetime, stream: :integer}

    {%{pos: nil, stream: nil}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_inclusion(:stream, [0, 1])
    |> Changeset.apply_action(:create)
  end

  defp validate_snapshot_req_params(params) do
    types = %{
      time: :utc_datetime,
      method: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: ~w(before precise)a)},
      format: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: ~w(jpeg png)a)}
    }

    {%{method: :before, format: :jpeg, time: nil}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.apply_action(:create)
  end

  defp validate_footage_req_params(params) do
    types = %{
      start_date: :utc_datetime,
      end_date: :utc_datetime,
      duration: :integer
    }

    {%{}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_required([:start_date])
    |> Changeset.validate_number(:duration, greater_than: 5, less_than_or_equal_to: 7200)
    |> validate_end_date_or_duration()
    |> Changeset.apply_action(:create)
  end

  defp validate_end_date_or_duration(%{valid?: false} = changeset), do: changeset

  defp validate_end_date_or_duration(changeset) do
    start_date = Changeset.get_change(changeset, :start_date)
    end_date = Changeset.get_change(changeset, :end_date)
    duration = Changeset.get_change(changeset, :duration)

    cond do
      is_nil(end_date) and is_nil(duration) ->
        Changeset.add_error(
          changeset,
          :end_date,
          "At least one field should be provided: end_date or duration",
          validation: :required
        )

      not is_nil(end_date) and
          (DateTime.diff(end_date, start_date) < 5 or DateTime.diff(end_date, start_date) > 7200) ->
        Changeset.add_error(
          changeset,
          :end_date,
          "The duration should be at least 5 seconds and at most 2 hours",
          validation: :format
        )

      true ->
        changeset
    end
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
