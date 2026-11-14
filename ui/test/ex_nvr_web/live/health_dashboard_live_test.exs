defmodule ExNVRWeb.HealthDashboardLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "redirects to login when unauthenticated", %{conn: _conn} do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/login"}}} = live(conn, ~p"/health")
  end

  test "mounts and renders the core panels", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/health")

    assert html =~ "System Health"
    assert html =~ "Device"
    assert html =~ "CPU"
    assert html =~ "Memory"
    assert html =~ "Storage"
    assert html =~ "Cameras"
    assert html =~ "Sparkline window"
  end

  test "broadcasts on the SystemStatus topic update the view", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/health")

    Phoenix.PubSub.broadcast(
      ExNVR.PubSub,
      ExNVR.SystemStatus.topic(),
      {:system_status, %{hostname: "broadcast-host"}}
    )

    html = render(lv)
    assert html =~ "broadcast-host"
  end
end
