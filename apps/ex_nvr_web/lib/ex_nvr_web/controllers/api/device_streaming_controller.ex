defmodule ExNVRWeb.API.DeviceStreamingController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  require Logger

  alias Ecto.Changeset
  alias ExNVR.Pipelines.{HlsPlayback, Main}
  alias ExNVR.{Devices, HLS, Recordings, Utils, VideoAssembler}

  @type return_t :: Plug.Conn.t() | {:error, Changeset.t()}

  @default_end_date ~U(2099-01-01 00:00:00Z)
  @seconds_in_year 3_600 * 24 * 365

  @spec hls_stream(Plug.Conn.t(), map()) :: return_t()
  def hls_stream(conn, params) do
    with {:ok, params} <- validate_hls_stream_params(params),
         query_params <- [stream_id: Utils.generate_token(), live: is_nil(params.pos)],
         {:ok, path} <- start_hls_pipeline(conn.assigns.device, params, query_params[:stream_id]),
         {:ok, manifest_file} <- File.read(Path.join(path, "index.m3u8")) do
      conn
      |> put_resp_content_type("application/vnd.apple.mpegurl")
      |> send_resp(
        200,
        remove_unused_stream(manifest_file, params)
        |> HLS.Processor.add_query_params(:playlist, query_params)
      )
    end
  end

  @spec hls_stream_segment(Plug.Conn.t(), map()) :: return_t()
  def hls_stream_segment(
        conn,
        %{"stream_id" => stream_id, "segment_name" => segment_name} = params
      ) do
    folder = if params["live"] == "true", do: "live", else: stream_id
    path = Path.join([Utils.hls_dir(conn.assigns.device.id), folder, segment_name])

    case File.exists?(path) do
      true ->
        if String.ends_with?(segment_name, ".m3u8") do
          ExNVRWeb.HlsStreamingMonitor.update_last_access_time(stream_id)

          path
          |> File.read!()
          |> HLS.Processor.add_query_params(:media_playlist,
            stream_id: stream_id,
            live: params["live"]
          )
          |> then(&send_resp(conn, 200, &1))
        else
          send_file(conn, 200, path)
        end

      false ->
        {:error, :not_found}
    end
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

  defp serve_live_snapshot(conn, params) do
    device = conn.assigns.device

    with {:error, _details} <- Devices.fetch_snapshot(device),
         :recording <- device.state do
      {:ok, snapshot} = Main.live_snapshot(device, params.format)

      conn
      |> put_resp_content_type("image/#{params.format}")
      |> send_resp(:ok, snapshot)
    else
      {:ok, snapshot} ->
        conn
        |> put_resp_content_type("image/jpeg")
        |> send_resp(:ok, snapshot)

      _ ->
        {:error, :not_found}
    end
  end

  defp serve_snapshot_from_recorded_videos(conn, %{time: time} = params) do
    device = conn.assigns.device

    with [recording] <- Recordings.get_recordings_between(device.id, params.stream, time, time),
         {:ok, timestamp, snapshot} <-
           Recordings.Snapshooter.snapshot(device, recording, time, method: params.method) do
      conn
      |> put_resp_header("x-timestamp", "#{DateTime.to_unix(timestamp, :millisecond)}")
      |> put_resp_content_type("image/jpeg")
      |> send_resp(:ok, snapshot)
    else
      [] -> {:error, :not_found}
      _other -> {:error, :no_jpeg}
    end
  end

  @spec footage(Plug.Conn.t(), map()) :: return_t()
  def footage(conn, params) do
    device = conn.assigns.device
    destination = Path.join(System.tmp_dir!(), UUID.uuid4() <> ".mp4")

    with {:ok, params} <- validate_footage_req_params(params),
         {:ok, recordings} <- get_recordings(device, params) do
      {_adapter, adapter_data} = conn.adapter

      # delete created file
      spawn(fn ->
        ref = Process.monitor(adapter_data.pid)

        receive do
          {:DOWN, ^ref, :process, _, _} -> :ok = File.rm!(destination)
        end
      end)

      {:ok, start_date} =
        VideoAssembler.Native.assemble_recordings(
          recordings,
          DateTime.to_unix(params.start_date, :millisecond),
          DateTime.to_unix(params.end_date || @default_end_date, :millisecond),
          params.duration || 0,
          destination
        )

      filename =
        start_date
        |> DateTime.from_unix!(:millisecond)
        |> Calendar.strftime("%Y%m%d%H%M%S.mp4")

      conn
      |> put_resp_header("x-start-date", "#{start_date}")
      |> send_download({:file, destination}, content_type: "video/mp4", filename: filename)
    end
  end

  defp get_recordings(device, params) do
    case Recordings.get_recordings_between(
           device.id,
           params.stream,
           params.start_date,
           params.end_date || @default_end_date,
           limit: 120
         ) do
      [] ->
        {:error, :not_found}

      recordings ->
        recordings =
          Enum.map(
            recordings,
            &VideoAssembler.Download.new(
              &1.start_date,
              &1.end_date,
              Recordings.recording_path(device, params.stream, &1)
            )
          )

        {:ok, recordings}
    end
  end

  @spec bif(Plug.Conn.t(), map()) :: return_t()
  def bif(conn, params) do
    with {:ok, params} <- validate_bif_req_params(params) do
      filename = Calendar.strftime(params.hour, "%Y%m%d%H.bif")
      filepath = Path.join(ExNVR.Model.Device.bif_dir(conn.assigns.device), filename)

      if File.exists?(filepath) do
        conn
        |> put_resp_header("cache-control", "private, immutable, max-age=#{@seconds_in_year}")
        |> send_download({:file, filepath}, filename: filename)
      else
        {:error, :not_found}
      end
    end
  end

  defp validate_hls_stream_params(params) do
    types = %{
      pos: :utc_datetime,
      stream: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: ~w(high low auto)a)},
      resolution: :integer,
      duration: :integer
    }

    {%{pos: nil, stream: nil, resolution: nil, duration: 0}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_inclusion(:resolution, [240, 480, 640, 720, 1080])
    |> Changeset.validate_number(:duration, greater_than_or_equal_to: 5)
    |> Changeset.apply_action(:create)
  end

  defp validate_snapshot_req_params(params) do
    types = %{
      time: :utc_datetime_usec,
      method: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: ~w(before precise)a)},
      format: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: ~w(jpeg)a)},
      stream: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: ~w(high low)a)}
    }

    {%{method: :before, format: :jpeg, time: nil, stream: :high}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.apply_action(:create)
  end

  defp validate_footage_req_params(params) do
    types = %{
      start_date: :utc_datetime_usec,
      end_date: :utc_datetime_usec,
      duration: :integer,
      stream: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: ~w(high low)a)}
    }

    {%{duration: 0, end_date: ~U(2099-01-01 00:00:00Z), stream: :high}, types}
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

  defp validate_bif_req_params(params) do
    types = %{hour: :utc_datetime}

    {%{}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_required([:hour])
    |> Changeset.apply_action(:create)
  end

  defp start_hls_pipeline(device, %{pos: nil}, stream_id) do
    ExNVRWeb.HlsStreamingMonitor.register(stream_id, fn -> :ok end)
    {:ok, Path.join(Utils.hls_dir(device.id), "live")}
  end

  defp start_hls_pipeline(device, params, stream_id) do
    case get_stream(params, device) do
      :error ->
        {:error, :not_found}

      stream ->
        path = Utils.hls_dir(device.id) |> Path.join(stream_id)

        pipeline_options = [
          device: device,
          start_date: params.pos,
          duration: params.duration,
          resolution: params.resolution,
          stream: stream,
          directory: path,
          segment_name_prefix: UUID.uuid4()
        ]

        {:ok, _, pid} = HlsPlayback.start(pipeline_options)

        ExNVRWeb.HlsStreamingMonitor.register(stream_id, fn -> HlsPlayback.stop_streaming(pid) end)

        :ok = HlsPlayback.start_streaming(pid)

        {:ok, path}
    end
  end

  defp get_stream(params, device) do
    stream = params.stream || :high

    cond do
      stream == :auto and Recordings.exists?(device, :low, params.pos) ->
        :low

      stream == :auto and Recordings.exists?(device, :high, params.pos) ->
        :high

      stream != :auto and Recordings.exists?(device, stream, params.pos) ->
        stream

      true ->
        :error
    end
  end

  defp remove_unused_stream(manifest_file, %{pos: pos}) when not is_nil(pos), do: manifest_file

  defp remove_unused_stream(manifest_file, %{stream: :high}),
    do: HLS.Processor.delete_stream(manifest_file, "live_sub_stream")

  defp remove_unused_stream(manifest_file, %{stream: :low}),
    do: HLS.Processor.delete_stream(manifest_file, "live_main_stream")

  defp remove_unused_stream(manifest_file, _params), do: manifest_file
end
