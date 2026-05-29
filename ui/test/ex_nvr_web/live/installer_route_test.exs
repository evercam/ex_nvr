defmodule ExNVRWeb.InstallerRouteTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ExNVR.InstallerMode

  setup do
    InstallerMode.disable()
    on_exit(&InstallerMode.disable/0)
    :ok
  end

  test "redirects to login when installer mode is off", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/users/login", flash: flash}}} =
             live(conn, ~p"/installer")

    assert %{"error" => "Installer mode is not enabled on this device."} = flash
  end

  test "renders the installer dashboard when installer mode is on", %{conn: conn} do
    InstallerMode.enable()

    {:ok, _lv, html} = live(conn, ~p"/installer")

    assert html =~ "Installer Mode"
    assert html =~ "Cameras"
    assert html =~ "Device"
    assert html =~ "Storage"
  end

  test "sign-in page advertises the installer link when enabled", %{conn: conn} do
    InstallerMode.enable()

    {:ok, _lv, html} = live(conn, ~p"/users/login")

    assert html =~ "Open Installer view"
  end

  test "sign-in page hides the installer link when disabled", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/login")

    refute html =~ "Open Installer view"
  end
end
