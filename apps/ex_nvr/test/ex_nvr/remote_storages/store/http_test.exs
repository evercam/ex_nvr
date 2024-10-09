defmodule ExNVR.RemoteStorages.Store.HTTPTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.{DevicesFixtures, RecordingsFixtures}

  alias ExNVR.RemoteStorages.Store.HTTP
  alias Plug.{Conn, Parsers.MULTIPART}

  @moduletag :tmp_dir

  @recording_path "/recordings"

  describe "save recording" do
    setup %{tmp_dir: tmp_dir} do
      bypass = Bypass.open()
      device = camera_device_fixture(tmp_dir)

      %{bypass: bypass, device: device}
    end

    test "recording is sent as a multipart", %{bypass: bypass, device: device} do
      recording = recording_fixture(device, start_date: ~U(2024-02-15 08:00:00Z))
      recording_path = ExNVR.Recordings.recording_path(device, recording)
      filename = Path.basename(recording_path)

      Bypass.expect_once(bypass, "POST", @recording_path, fn conn ->
        assert {:ok, %{"file" => upload, "metadata" => metadata}, conn} =
                 MULTIPART.parse(conn, "multipart", "form-data", [], MULTIPART.init([]))

        assert {:ok, %{device_id: device.id, start_date: "2024-02-15T08:00:00.000000Z"}} ==
                 Jason.decode(metadata, keys: :atoms!)

        assert %Plug.Upload{content_type: "video/mp4", filename: ^filename, path: path} = upload

        assert File.exists?(path)
        assert File.read!(path) == File.read!(recording_path)

        Conn.resp(conn, 204, "")
      end)

      assert :ok =
               HTTP.save_recording(device, recording,
                 url: endpoint_url(bypass.port, @recording_path)
               )
    end

    test "remote storage returns error", %{bypass: bypass, device: device} do
      recording = recording_fixture(device, start_date: ~U(2024-02-15 08:00:00Z))

      Bypass.expect_once(bypass, "POST", @recording_path, fn conn -> Conn.resp(conn, 400, "") end)

      assert {:error, %{status: 400}} =
               HTTP.save_recording(device, recording,
                 url: endpoint_url(bypass.port, @recording_path)
               )
    end

    test "remote storage is down", %{bypass: bypass, device: device} do
      recording = recording_fixture(device, start_date: ~U(2024-02-15 08:00:00Z))

      Bypass.down(bypass)

      assert {:error, %Mint.TransportError{reason: :econnrefused}} =
               HTTP.save_recording(device, recording,
                 url: endpoint_url(bypass.port, @recording_path)
               )
    end
  end

  defp endpoint_url(port, path), do: "http://localhost:#{port}/#{path}"
end
