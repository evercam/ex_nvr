defmodule ExNVRWeb.RemoteStoragesListLiveTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, RemoteStoragesFixtures}
  import Phoenix.LiveViewTest

  describe "Remote storage list page" do
    setup do
      %{remote_storage: remote_storage_fixture()}
    end

    test "render remote storages page", %{conn: conn, remote_storage: remote_storage} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/remote-storages")

      assert html =~ "Add remote storage"
      assert html =~ remote_storage.name
      assert html =~ Atom.to_string(remote_storage.type)
      assert html =~ Integer.to_string(remote_storage.id)
    end

    test "redirect if user is not logged in", %{conn: conn} do
      {:error, redirect} = live(conn, ~p"/remote-storages")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/login"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirect when clicking on add remote storage", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/remote-storages")

      {:error, redirect} =
        lv
        |> element(~s|a[href="/remote-storages/new"]|)
        |> render_click()

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/remote-storages/new"
    end
  end
end
