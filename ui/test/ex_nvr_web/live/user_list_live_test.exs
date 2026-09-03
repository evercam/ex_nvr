defmodule ExNVRWeb.UserListLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures}
  import Phoenix.LiveViewTest

  describe "Users list page" do
    setup do
      %{admin: user_fixture()}
    end

    test "unauthorized error for non admins", %{conn: conn} do
      {:error, redirect} =
        conn
        |> log_in_user(user_fixture(%{role: :user}))
        |> live(~p"/users")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/dashboard"
      assert %{"error" => "You can't access this page."} = flash
    end

    test "render users page", %{conn: conn, admin: admin} do
      user = user_fixture(%{role: :user})

      {:ok, _lv, html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users")

      assert html =~ "Add User"
      assert html =~ admin.id
      assert html =~ admin.first_name
      assert html =~ admin.email
      assert html =~ String.upcase(Atom.to_string(admin.role))

      assert html =~ user.id
      assert html =~ user.first_name
      assert html =~ user.email
      assert html =~ String.upcase(Atom.to_string(user.role))
    end

    test "redirect when clicking on add user", %{conn: conn, admin: admin} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users")

      {:error, redirect} =
        lv
        |> element(~s|a[href="/users/new"]|)
        |> render_click()

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/users/new"
    end
  end

  describe "User deletion/update" do
    setup %{conn: conn} do
      admin = user_fixture()
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "Delete user", %{conn: conn, admin: admin} do
      user = user_fixture(%{role: :user})
      {:ok, lv, html} = live(conn, ~p"/users")

      assert html =~ "Delete"

      assert lv
             |> element("#delete_user-#{user.id}", "Delete")
             |> has_element?()

      assert {:ok, _deleted_user} = ExNVR.Accounts.delete_user(user)

      users = ExNVR.Accounts.list()
      assert length(users) == 1
      [current_user] = users
      assert current_user.id == admin.id
    end
  end
end
