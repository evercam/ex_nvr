defmodule ExNVRWeb.API.OnvifControllerTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
  import ExNVR.Onvif.TestUtils
  import Mock

  alias ExNVR.Onvif

  @discovered_devices [
    %{
      name: "Camera 1",
      hardware: "HW1",
      url: "http://192.168.1.100/onvif/device_service"
    },
    %{
      name: "Camera 2",
      hardware: "HW2",
      url: "http://192.168.1.101/onvif/device_service"
    }
  ]

  @media_url "http://192.168.1.100/onvif/Media"

  setup do
    conn = build_conn() |> log_in_user_with_access_token(user_fixture())
    %{conn: conn}
  end

  describe "GET/POST /api/onvif/discover" do
    setup_with_mocks([
      {ExNVR.Onvif, [],
       [
         discover: fn _opts -> {:ok, @discovered_devices} end,
         get_system_date_and_time: fn _url -> date_time_response_mock() end,
         get_device_information: fn _url, _opts -> device_information_response_mock() end,
         get_network_interfaces: fn _url, _opts -> network_interfaces_response_mock() end,
         get_capabilities: fn _url, _opts -> capabilities_response_mock() end,
         get_media_profiles: fn @media_url, _opts -> profiles_response_mock() end,
         get_media_stream_uri!: fn @media_url, _profile, _opts -> stream_uri_response() end,
         get_media_snapshot_uri!: fn @media_url, _profile, _opts ->
           snapshot_uri_response_mock()
         end
       ]}
    ]) do
      :ok
    end

    test "discover devices", %{conn: conn} do
      response =
        conn
        |> post("/api/onvif/discover", %{timeout: 2, username: "admin", password: "pass"})
        |> json_response(200)

      assert Enum.map(response, & &1["name"]) == ["Camera 1", "Camera 2"]

      assert Enum.map(response, & &1["url"]) == [
               "http://192.168.1.100/onvif/device_service",
               "http://192.168.1.101/onvif/device_service"
             ]

      assert_called_exactly(Onvif.discover(timeout: 2_000), 1)
      assert_called_exactly(Onvif.get_system_date_and_time(:_), 2)
      assert_called_exactly(Onvif.get_device_information(:_, :_), 2)
      assert_called_exactly(Onvif.get_network_interfaces(:_, :_), 2)
      assert_called_exactly(Onvif.get_capabilities(:_, :_), 2)
      assert_called_exactly(Onvif.get_media_profiles(:_, :_), 2)
      assert_called_exactly(Onvif.get_media_stream_uri!(:_, :_, :_), 4)
      assert_called_exactly(Onvif.get_media_snapshot_uri!(:_, :_, :_), 4)
    end

    test "discover devices not allowed for non admin users" do
      build_conn()
      |> log_in_user_with_access_token(user_fixture(role: :user))
      |> post("/api/onvif/discover", %{timeout: 2, username: "admin", password: "pass"})
      |> json_response(403)

      assert_not_called(Onvif.discover(:_))
    end
  end
end
