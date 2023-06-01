defmodule ExNVRWeb.API.RecordingControllerTest do
  use ExNVRWeb.ConnCase

  alias ExNVR.{AccountsFixtures, RecordingsFixtures}
  alias Faker.Random

  setup_all do
    on_exit(fn -> clean_recording_directory() end)
  end

  setup do
    conn = build_conn() |> log_in_user_with_access_token(AccountsFixtures.user_fixture())
    device = create_device!()

    File.mkdir_p!(ExNVR.Utils.recording_dir(device.id))
    %{conn: conn, device: device}
  end

  describe "GET /api/devices/:device_id/recordings" do
    setup %{device: device} do
      RecordingsFixtures.run_fixture(
        device_id: device.id,
        start_date: ~U(2023-05-01 01:52:00.000000Z),
        end_date: ~U(2023-05-02 10:15:30.000000Z)
      )

      RecordingsFixtures.run_fixture(
        device_id: device.id,
        start_date: ~U(2023-05-03 20:12:00.000000Z),
        end_date: ~U(2023-05-03 21:10:30.000000Z)
      )

      RecordingsFixtures.run_fixture(
        device_id: device.id,
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

  describe "GET /api/devices/:device_id/recordings/:recording_id/blob" do
    setup do
      %{user: AccountsFixtures.user_fixture()}
    end

    test "get recording blob", %{device: device, conn: conn} do
      content = Random.Elixir.random_bytes(20)
      file_path = create_temp_file!(content)
      recording = create_recording!(device_id: device.id, path: file_path)

      response =
        conn
        |> get("/api/devices/#{device.id}/recordings/#{recording.filename}/blob")
        |> response(200)

      assert response == content

      File.rm!(file_path)
    end

    test "get blob of not existing recording", %{device: device, conn: conn} do
      conn
      |> get("/api/devices/#{device.id}/recordings/#{UUID.uuid4()}/blob")
      |> response(404)
    end
  end
end
