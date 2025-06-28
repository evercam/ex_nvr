defmodule ExNVRWeb.API.DeviceStreamingControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures, RecordingsFixtures}

  alias ExNVR.Model.Device
  alias Plug.Conn

  @moduletag :tmp_dir
  @moduletag :device

  @manifest """
  #EXTM3U
  #EXT-X-VERSION:7
  #EXT-X-INDEPENDENT-SEGMENTS
  #EXT-X-STREAM-INF:BANDWIDTH=1138520,CODECS="avc1.42e00a"
  main_stream.m3u8
  #EXT-X-STREAM-INF:BANDWIDTH=138520,CODECS="avc1.42e00a"
  sub_stream.m3u8
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

      body = response(conn, 200)

      assert body =~ "main_stream.m3u8"
      assert body =~ "sub_stream.m3u8"
    end

    test "get manifest file for not recorded date", %{conn: conn, device: device} do
      conn
      |> get(~p"/api/devices/#{device.id}/hls/index.m3u8?pos=2050-01-01T10:00:00Z")
      |> json_response(404)
    end

    test "get manifest file for selected stream", %{conn: conn, device: device} do
      response =
        conn
        |> get(~p"/api/devices/#{device.id}/hls/index.m3u8?stream=high")
        |> response(200)

      assert response =~ "main_stream.m3u8"
      refute response =~ "sub_stream.m3u8"

      response =
        conn
        |> get(~p"/api/devices/#{device.id}/hls/index.m3u8?stream=low")
        |> response(200)

      refute response =~ "main_stream.m3u8"
      assert response =~ "sub_stream.m3u8"
    end

    test "get manifest file with invalid params", %{conn: conn, device: device} do
      response =
        conn
        |> get(~p"/api/devices/#{device.id}/hls/index.m3u8?stream=lo")
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end
  end

  describe "GET /api/devices/:device_id/snapshot" do
    setup %{device: device} do
      bypass = Bypass.open()

      recording =
        recording_fixture(device, %{
          start_date: ~U(2023-06-23 20:00:00Z),
          end_date: ~U(2023-06-23 20:00:05Z)
        })

      low_stream_recording =
        recording_fixture(device, %{
          start_date: ~U(2023-06-23 20:00:00Z),
          end_date: ~U(2023-06-23 20:00:05Z),
          stream: :low
        })

      %{recording: recording, low_stream_recording: low_stream_recording, bypass: bypass}
    end

    test "Get snapshot from recorded videos", %{conn: conn, device: device, recording: recording} do
      conn = get(conn, "/api/devices/#{device.id}/snapshot?time=#{recording.start_date}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/jpeg; charset=utf-8"]

      input_timestamp = recording.start_date |> DateTime.to_unix(:millisecond)
      [resp_timestamp] = conn |> get_resp_header("x-timestamp")

      assert resp_timestamp == "#{input_timestamp}"
    end

    test "Get snapshot from recorded sub stream videos", %{
      conn: conn,
      device: device,
      recording: recording
    } do
      conn =
        get(conn, "/api/devices/#{device.id}/snapshot?time=#{recording.start_date}&stream=low")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/jpeg; charset=utf-8"]

      input_timestamp = recording.start_date |> DateTime.to_unix(:millisecond)
      [resp_timestamp] = get_resp_header(conn, "x-timestamp")

      assert resp_timestamp == "#{input_timestamp}"
    end

    test "Returns 404 if there's no recording", %{conn: conn, device: device} do
      conn
      |> get("/api/devices/#{device.id}/snapshot?time=#{DateTime.utc_now()}")
      |> response(404)
    end

    test "Returns 404 if the device is not recording when requesting live snapshot", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      device = camera_device_fixture(tmp_dir, %{state: :failed})

      conn
      |> get("/api/devices/#{device.id}/snapshot")
      |> response(404)
    end

    test "Get live snapshot from camera using snapshot uri", %{
      conn: conn,
      tmp_dir: tmp_dir,
      bypass: bypass
    } do
      device =
        camera_device_fixture(tmp_dir, %{
          stream_config: %{
            stream_uri: "rtsp://localhost:8541",
            snapshot_uri: "http://localhost:#{bypass.port}/snapshot"
          }
        })

      Bypass.expect(bypass, "GET", "/snapshot", fn conn ->
        conn
        |> Conn.put_resp_content_type("image/jpeg")
        |> Conn.resp(200, <<20, 12, 23>>)
      end)

      req_timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      conn = get(conn, "/api/devices/#{device.id}/snapshot")
      assert get_resp_header(conn, "content-type") == ["image/jpeg; charset=utf-8"]

      assert %{
               status: 200,
               resp_body: <<20, 12, 23>>
             } = conn

      {resp_timestamp, _} = get_resp_header(conn, "x-timestamp") |> Enum.at(0) |> Integer.parse()
      assert resp_timestamp - req_timestamp < 1000
    end
  end

  describe "GET /api/devices/:device_id/footage" do
    setup %{device: device} do
      recording_fixture(device, %{
        start_date: ~U(2023-06-23 20:00:00Z),
        end_date: ~U(2023-06-23 20:00:05Z)
      })

      recording_fixture(device, %{
        start_date: ~U(2023-06-23 20:00:05Z),
        end_date: ~U(2023-06-23 20:00:10Z)
      })

      recording_fixture(device, %{
        start_date: ~U(2023-06-23 20:00:13Z),
        end_date: ~U(2023-06-23 20:00:18Z)
      })

      :ok
    end

    test "Get footage", %{conn: conn, device: device} do
      params = %{
        start_date: ~U(2023-06-23 20:00:03Z),
        end_date: ~U(2023-06-23 20:00:14Z)
      }

      conn = get(conn, "/api/devices/#{device.id}/footage", params)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["video/mp4"]
    end

    test "Bad request: duration or end date should be provided", %{conn: conn, device: device} do
      params = %{start_date: ~U(2023-06-23 20:00:03Z)}

      response =
        conn
        |> get("/api/devices/#{device.id}/footage", params)
        |> json_response(400)

      assert List.first(response["details"])["message"] =~ "one field should be provided"
    end

    test "Bad request: duration should be between 5 seconds and 2 hours", %{
      conn: conn,
      device: device
    } do
      params = %{start_date: ~U(2023-06-23 20:00:03Z), duration: 3}

      response =
        conn
        |> get("/api/devices/#{device.id}/footage", params)
        |> json_response(400)

      assert List.first(response["details"])["message"] =~ "must be greater than 5"

      response =
        conn
        |> get("/api/devices/#{device.id}/footage", %{params | duration: 7230})
        |> json_response(400)

      assert List.first(response["details"])["message"] =~ "must be less than or equal to 7200"
    end

    test "Bad request: start date to end date should be between 5 seconds and 2 hours", %{
      conn: conn,
      device: device
    } do
      params = %{start_date: ~U(2023-06-23 20:00:03Z), end_date: ~U(2023-06-23 20:00:05Z)}

      response =
        conn
        |> get("/api/devices/#{device.id}/footage", params)
        |> json_response(400)

      assert List.first(response["details"])["message"] =~
               "The duration should be at least 5 seconds and at most 2 hours"

      response =
        conn
        |> get("/api/devices/#{device.id}/footage", %{params | end_date: ~U(2023-06-23 22:00:05Z)})
        |> json_response(400)

      assert List.first(response["details"])["message"] =~
               "The duration should be at least 5 seconds and at most 2 hours"
    end
  end

  describe "GET /api/devices/:device_id/bif/:hour" do
    setup %{device: device} do
      Path.join(Device.bif_dir(device), "2023083110.bif") |> File.touch!()
    end

    test "Get bif file", %{conn: conn, device: device} do
      conn = get(conn, "/api/devices/#{device.id}/bif/2023-08-31T10:00:03Z")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    end

    test "Resource doesn't exissts", %{conn: conn, device: device} do
      conn
      |> get("/api/devices/#{device.id}/bif/2023-08-31T12:00:03Z")
      |> response(:not_found)
    end
  end
end
