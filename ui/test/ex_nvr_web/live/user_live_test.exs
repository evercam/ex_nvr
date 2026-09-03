defmodule ExNVRWeb.UserLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures}
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    admin = user_fixture()
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  describe "User page" do
    test "unauthorized for non admins", %{conn: conn} do
      {:error, redirect} =
        conn
        |> log_in_user(user_fixture(%{role: :user}))
        |> live(~p"/users/new")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/dashboard"
      assert %{"error" => "You can't access this page."} = flash
    end

    test "render new user page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/new")

      assert html =~ "Create a new user"
      assert html =~ "Creating..."
    end

    test "render update user page", %{conn: conn} do
      user = user_fixture()
      {:ok, _lv, html} = live(conn, ~p"/users/#{user.id}")

      assert html =~ "Update a user"
      assert html =~ "Updating..."
    end
  end

  describe "Create user" do
    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/new")

      result =
        lv
        |> form("#user_form", %{
          "user" => %{
            "first_name" => "M",
            "last_name" => "S",
            "email" => "with spaces",
            "password" => "short",
            "role" => "user",
            "language" => "en"
          }
        })
        |> render_submit()

      assert result =~ "should be at least 2 character"
      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "should be at least 8 character(s)"
      assert result =~ "at least one upper case character"
      assert result =~ "at least one digit or punctuation character"
    end

    test "creates a user successfully", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/new")

      {:ok, conn} =
        lv
        |> form("#user_form", user: valid_user_full_attributes())
        |> render_submit()
        |> follow_redirect(conn, ~p"/users")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "User created successfully"

      users = ExNVR.Accounts.list()
      assert length(users) == 2
    end
  end

  describe "Update user" do
    setup do
      %{user: user_fixture(%{role: :user})}
    end

    test "renders errors for invalid data", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/users/#{user.id}")

      refute html =~ "Password"

      result =
        lv
        |> form("#user_form", %{
          "user" => %{
            "first_name" => "M",
            "last_name" => "S",
            "email" => "with spaces",
            "role" => "user",
            "language" => "en"
          }
        })
        |> render_submit()

      assert result =~ "should be at least 2 character"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "updates a user successfully", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/#{user.id}")

      {:ok, conn} =
        lv
        |> form("#user_form", %{
          "user" => %{
            "first_name" => "updated_name",
            "last_name" => "updated_last_name",
            "email" => "updated_email@email.com",
            "role" => "admin",
            "language" => "en"
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/users")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "User updated successfully"

      updated_user = ExNVR.Accounts.get_user!(user.id)
      assert updated_user.first_name == "updated_name"
      assert updated_user.last_name == "updated_last_name"
      assert updated_user.email == "updated_email@email.com"
      assert updated_user.role == :admin
    end
  end
end
