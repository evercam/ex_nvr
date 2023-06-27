defmodule ExNVRWeb.API.DeviceStreamingControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures, RecordingsFixtures}

  @moduletag :tmp_dir
  @moduletag :device

  @manifest """
  #EXTM3U
  #EXT-X-VERSION:7
  #EXT-X-INDEPENDENT-SEGMENTS
  #EXT-X-STREAM-INF:BANDWIDTH=1138520,CODECS="avc1.42e00a"
  live_main_stream.m3u8
  #EXT-X-STREAM-INF:BANDWIDTH=138520,CODECS="avc1.42e00a"
  live_sub_stream.m3u8
  """

  @manifest_main_stream """
  #EXTM3U
  #EXT-X-VERSION:7
  #EXT-X-INDEPENDENT-SEGMENTS
  #EXT-X-STREAM-INF:BANDWIDTH=1138520,CODECS="avc1.42e00a"
  live_main_stream.m3u8
  """

  @manifest_sub_stream """
  #EXTM3U
  #EXT-X-VERSION:7
  #EXT-X-INDEPENDENT-SEGMENTS
  #EXT-X-STREAM-INF:BANDWIDTH=138520,CODECS="avc1.42e00a"
  live_sub_stream.m3u8
  """

  setup %{conn: conn} do
    %{conn: log_in_user_with_access_token(conn, user_fixture())}
  end

  describe "GET /api/devices/:device_id/hls/index.m3u8" do
    setup %{device: device} do
      Path.join(ExNVR.Utils.hls_dir(device.id), "live")
      |> tap(&File.mkdir_p!/1)
      |> Path.join("index.m3u8")
      |> File.write!(@manifest)

      :ok
    end

    test "get manifest file", %{conn: conn, device: device} do
      conn = get(conn, ~p"/api/devices/#{device.id}/hls/index.m3u8")

      assert ["application/vnd.apple.mpegurl; charset=utf-8"] =
               get_resp_header(conn, "content-type")

      assert response(conn, 200) == @manifest
    end

    test "get manifest file for selected stream", %{conn: conn, device: device} do
      response =
        conn
        |> get(~p"/api/devices/#{device.id}/hls/index.m3u8?stream=0")
        |> response(200)

      assert response == @manifest_main_stream

      response =
        conn
        |> get(~p"/api/devices/#{device.id}/hls/index.m3u8?stream=1")
        |> response(200)

      assert response == @manifest_sub_stream
    end

    test "get manifest file with invalid params", %{conn: conn, device: device} do
      response =
        conn
        |> get(~p"/api/devices/#{device.id}/hls/index.m3u8?stream=2")
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end
  end

  describe "GET /api/devices/:device_id/snapshot" do
    setup %{device: device} do
      recording =
        recording_fixture(device, %{
          start_date: ~U(2023-06-23 20:00:00Z),
          end_date: ~U(2023-06-23 20:00:05Z)
        })

      %{recording: recording}
    end

    test "Get snapshot from recorded videos", %{conn: conn, device: device, recording: recording} do
      conn = get(conn, "/api/devices/#{device.id}/snapshot?time=#{recording.start_date}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/jpeg; charset=utf-8"]
    end

    test "Returns 404 if there's no recording", %{conn: conn, device: device} do
      conn
      |> get("/api/devices/#{device.id}/snapshot?time=#{DateTime.utc_now()}")
      |> response(404)
    end

    test "Returns 404 if the device is not recording when requesting live snapshot", %{conn: conn} do
      device = device_fixture(%{state: :failed})

      conn
      |> get("/api/devices/#{device.id}/snapshot")
      |> response(404)
    end
  end
end
