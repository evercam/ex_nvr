defmodule ExNVRWeb.API.RecordingControllerTest do
  use ExNVRWeb.ConnCase

  alias ExNVR.AccountsFixtures
  alias Faker.Random

  setup_all do
    on_exit(fn -> clean_recording_directory() end)
  end

  setup do
    conn = build_conn() |> log_in_user_with_access_token(AccountsFixtures.user_fixture())
    %{conn: conn}
  end

  describe "GET /api/devices/:device_id/recordings/:recording_id/blob" do
    setup do
      device = create_device!()
      %{device: device, user: AccountsFixtures.user_fixture()}
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
