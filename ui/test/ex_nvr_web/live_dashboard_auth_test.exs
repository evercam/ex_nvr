defmodule ExNVRWeb.LiveDashboardAuthTest do
  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
  import Phoenix.LiveViewTest

  test "redirects unauthenticated users to login", %{conn: conn} do
    conn = get(conn, ~p"/live-dashboard")
    assert redirected_to(conn) == ~p"/users/login"
  end

  test "redirects regular users to the dashboard", %{conn: conn} do
    conn =
      conn
      |> log_in_user(user_fixture(%{role: :user}))
      |> get(~p"/live-dashboard")

    assert redirected_to(conn) == ~p"/dashboard"
  end

  test "allows admins", %{conn: conn} do
    conn =
      conn
      |> log_in_user(user_fixture())
      |> get(~p"/live-dashboard")

    assert conn.status in [200, 302]
    refute conn.status == 302 and redirected_to(conn) in [~p"/dashboard", ~p"/users/login"]
  end

  test "sidebar link is shown only to admins", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(user_fixture(%{role: :user})) |> live(~p"/dashboard")
    refute has_element?(lv, ~s|a[href="/live-dashboard"]|)

    {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/dashboard")
    assert has_element?(lv, ~s|a[href="/live-dashboard"]|)
  end
end
