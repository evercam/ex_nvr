defmodule ExNVRWeb.API.OnvifControllerTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
  import Mimic

  alias ExOnvif.Discovery.Probe

  @discovered_devices [
    %Probe{
      types: ["dn:NetworkVideoTransmitter", "tds:Device"],
      scopes: ["onvif://www.onvif.org/Profile/Streaming"],
      request_guid: "uuid:00000000-0000-0000-0000-000000000000",
      address: ["http://192.168.1.100/onvif/device_service"]
    },
    %Probe{
      types: ["dn:NetworkVideoTransmitter", "tds:Device"],
      scopes: ["onvif://www.onvif.org/Profile/Streaming"],
      request_guid: "uuid:00000000-0000-0000-0000-000000000001",
      address: ["http://192.168.1.101/onvif/device_service"]
    }
  ]

  setup do
    conn = build_conn() |> log_in_user_with_access_token(user_fixture())
    %{conn: conn}
  end

  describe "GET/POST /api/onvif/discover" do
    test "discover devices", %{conn: conn} do
      expect(ExOnvif.Discovery, :probe, fn [probe_timeout: 2_000] -> @discovered_devices end)

      expect(ExOnvif.Device, :init, fn probe, "admin", "pass" ->
        assert ["http://192.168.1.100/onvif/device_service"] = probe.address

        {:ok,
         %ExOnvif.Device{
           manufacturer: "Hikvision",
           address: List.first(probe.address),
           scopes: probe.scopes
         }}
      end)
      |> expect(:init, fn probe, "admin", "pass" ->
        assert ["http://192.168.1.101/onvif/device_service"] = probe.address
        {:error, "Invalid Credentials"}
      end)

      response =
        conn
        |> post("/api/onvif/discover", %{timeout: 2, username: "admin", password: "pass"})
        |> json_response(200)

      assert Enum.map(response, & &1["address"]) == [
               "http://192.168.1.100/onvif/device_service",
               ["http://192.168.1.101/onvif/device_service"]
             ]

      assert Enum.map(response, & &1["manufacturer"]) == ["Hikvision", nil]
    end

    test "discover devices not allowed for non admin users" do
      build_conn()
      |> log_in_user_with_access_token(user_fixture(role: :user))
      |> post("/api/onvif/discover", %{timeout: 2, username: "admin", password: "pass"})
      |> json_response(403)
    end
  end
end
