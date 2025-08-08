defmodule ExNVRWeb.API.RecordingControllerTest do
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, RecordingsFixtures}

  alias Faker.Random

  @moduletag :tmp_dir

  setup ctx do
    conn = build_conn() |> log_in_user_with_access_token(user_fixture())
    device = camera_device_fixture(ctx.tmp_dir)

    %{conn: conn, device: device}
  end

  describe "GET /api/devices/:device_id/recordings" do
    setup %{device: device} do
      run_fixture(device,
        start_date: ~U(2023-05-01 01:52:00.000000Z),
        end_date: ~U(2023-05-02 10:15:30.000000Z)
      )

      run_fixture(device,
        start_date: ~U(2023-05-01 01:52:00.000000Z),
        end_date: ~U(2023-05-02 10:15:30.000000Z),
        stream: :low
      )

      run_fixture(device,
        start_date: ~U(2023-05-03 20:12:00.000000Z),
        end_date: ~U(2023-05-03 21:10:30.000000Z)
      )

      run_fixture(device,
        start_date: ~U(2023-05-10 08:52:00.000000Z),
        end_date: ~U(2023-05-15 12:45:30.000000Z),
        active: true
      )

      :ok
    end

    test "get runs", %{device: device, conn: conn} do
      response =
        conn
        |> get("/api/devices/#{device.id}/recordings")
        |> json_response(200)

      assert length(response) == 3
      assert Enum.map(response, & &1["active"]) == [false, false, true]
    end

    test "get low resolution runs", %{device: device, conn: conn} do
      response =
        conn
        |> get("/api/devices/#{device.id}/recordings?stream=low")
        |> json_response(200)

      assert length(response) == 1
    end

    test "filter runs", %{device: device, conn: conn} do
      response =
        conn
        |> get("/api/devices/#{device.id}/recordings?start_date=2023-05-10 21:30:15")
        |> json_response(200)

      assert length(response) == 1

      assert [
               %{
                 "active" => true,
                 "start_date" => "2023-05-10T08:52:00.000000Z",
                 "end_date" => "2023-05-15T12:45:30.000000Z"
               }
             ] = response
    end
  end

  describe "GET /api/recordings/chunks" do
    setup ctx do
      device_1 = camera_device_fixture(ctx.tmp_dir)
      device_2 = camera_device_fixture(ctx.tmp_dir)
      device_3 = camera_device_fixture(ctx.tmp_dir)

      rec_1 = recording_fixture(device_1)
      rec_2 = recording_fixture(device_1)
      rec_3 = recording_fixture(device_2)
      rec_4 = recording_fixture(device_3)
      rec_5 = recording_fixture(device_3, stream: :low)

      %{recordings: [rec_1, rec_2, rec_3, rec_4], low_res_recordings: [rec_5], device: device_1}
    end

    test "get recordings chunks", %{
      conn: conn,
      recordings: recordings,
      low_res_recordings: low_res_recordings
    } do
      response =
        conn
        |> get("/api/recordings/chunks")
        |> json_response(200)

      assert length(response["data"]) == 4

      assert Enum.map(response["data"], & &1["id"]) |> MapSet.new() ==
               Enum.map(recordings, & &1.id) |> MapSet.new()

      assert %{
               "total_count" => 4,
               "total_pages" => 1,
               "current_page" => 1,
               "page_size" => 100
             } = response["meta"]

      # Low resolution chunks
      response =
        conn
        |> get("/api/recordings/chunks?stream=low")
        |> json_response(200)

      assert length(response["data"]) == length(low_res_recordings)

      assert Enum.map(response["data"], & &1["id"]) |> MapSet.new() ==
               Enum.map(low_res_recordings, & &1.id) |> MapSet.new()
    end

    test "filter recordings chunks", %{conn: conn, device: device, recordings: recordings} do
      response =
        conn
        |> get(
          "/api/recordings/chunks?filters[0][field]=device_id&filters[0][value]=#{device.id}"
        )
        |> json_response(200)

      assert length(response["data"]) == 2

      assert Enum.map(response["data"], & &1["id"]) |> MapSet.new() ==
               Enum.take(recordings, 2) |> Enum.map(& &1.id) |> MapSet.new()
    end

    test "invalid params", %{conn: conn} do
      response =
        conn
        |> get("/api/recordings/chunks?filters[0][field]=device&order_by=some_field")
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end
  end

  describe "GET /api/devices/:device_id/recordings/:recording_id/blob" do
    setup do
      %{user: user_fixture()}
    end

    test "get recording blob", %{tmp_dir: tmp_dir, device: device, conn: conn} do
      file_path = Path.join(tmp_dir, UUID.uuid4())
      content = Random.Elixir.random_bytes(20)
      File.write!(file_path, content)

      recording = recording_fixture(device, path: file_path)

      response =
        conn
        |> get("/api/devices/#{device.id}/recordings/#{recording.filename}/blob")
        |> response(200)

      assert response == content
    end

    test "get blob of not existing recording", %{device: device, conn: conn} do
      conn
      |> get("/api/devices/#{device.id}/recordings/#{UUID.uuid4()}/blob")
      |> response(404)
    end
  end
end
