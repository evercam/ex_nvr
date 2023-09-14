defmodule ExNVRWeb.OnvifDiscoveryLiveTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
  import Mock
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {:ok, conn: log_in_user(conn, user_fixture())}
  end

  test "render onvif discovery page", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/onvif-discovery")

    assert html =~ "Discover Devices"
    assert html =~ "Found Devices"
    assert html =~ "Device Details"

    assert lv
           |> form("#discover_form")
           |> has_element?()

    assert lv
           |> element("button", "Scan")
           |> has_element?()
  end

  describe "Discover devices" do
    setup_with_mocks([
      {ExNVR.Onvif, [],
       [
         discover: fn
           [timeout: 1000] ->
             {:ok,
              [
                %{
                  name: "Camera 1",
                  hardware: "HW1",
                  url: "http://192.168.1.100/onvif/device_service"
                },
                %{
                  name: "Camera 2",
                  hardware: "HW2",
                  url: "http://192.168.1.200/onvif/device_service"
                }
              ]}

           [timeout: 2000] ->
             {:error, "something is wrong"}
         end
       ]}
    ]) do
      :ok
    end

    test "render found devices", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      html =
        lv
        |> form("#discover_form")
        |> render_submit(%{"discover_settings" => %{"timeout" => "1"}})

      assert html =~ "Camera 1"
      assert html =~ "HW1"
      assert html =~ "http://192.168.1.100/onvif/device_service"

      assert html =~ "Camera 2"
      assert html =~ "HW2"
      assert html =~ "http://192.168.1.200/onvif/device_service"
    end

    test "render validation errors", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      html =
        lv
        |> form("#discover_form")
        |> render_submit(%{"discover_settings" => %{"timeout" => "0"}})

      refute html =~ "Camera 1"
      assert html =~ "is invalid"
    end

    test "render discovery errors as flash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      html =
        lv
        |> form("#discover_form")
        |> render_submit(%{"discover_settings" => %{"timeout" => "2"}})

      refute html =~ "Camera 1"
      refute html =~ "Camera 2"

      assert html =~ "Error occurred while discovering devices"
    end
  end
end
