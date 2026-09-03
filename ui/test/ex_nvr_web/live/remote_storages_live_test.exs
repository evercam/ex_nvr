defmodule ExNVRWeb.RemoteStoragesLiveTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, RemoteStoragesFixtures}
  import Phoenix.LiveViewTest

  alias ExNVR.RemoteStorages

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  describe "Remote storage page" do
    test "render new remote storage page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/remote-storages/new")

      assert html =~ "Create a new remote storage"
      assert html =~ "Creating..."
    end

    test "render update remote storage page", %{conn: conn} do
      remote_storage = remote_storage_fixture()
      {:ok, _lv, html} = live(conn, ~p"/remote-storages/#{remote_storage.id}")

      assert html =~ "Update a remote storage"
      assert html =~ "Updating..."
    end
  end

  describe "Create remote storage" do
    test "create a new s3 remote storage", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/remote-storages/new")

      {:ok, conn} =
        lv
        |> form("#remote_storage_form", %{
          "remote_storage" => %{
            "name" => "My remote storage",
            "type" => "s3",
            "url" => "https://localhost",
            "s3_config" => %{
              "bucket" => "my-bucket",
              "region" => "us-east-1",
              "access_key_id" => "ACCESSKEYID",
              "secret_access_key" => "SECRETACCESSKEY"
            }
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/remote-storages")

      remote_storages = RemoteStorages.list()
      assert length(remote_storages) == 1

      [created_remote_storage] = remote_storages

      assert created_remote_storage.name == "My remote storage"
      assert created_remote_storage.type == :s3
      assert created_remote_storage.url == "https://localhost"
      assert created_remote_storage.s3_config.bucket == "my-bucket"
      assert created_remote_storage.s3_config.access_key_id == "ACCESSKEYID"
      assert created_remote_storage.s3_config.secret_access_key == "SECRETACCESSKEY"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Remote storage created successfully"
    end
  end

  describe "Update a remote storage" do
    setup do
      %{
        remote_storage: remote_storage_fixture(%{name: "My original remote storage"}, "http")
      }
    end

    test "update a remote storage", %{conn: conn, remote_storage: remote_storage} do
      {:ok, lv, _} = live(conn, ~p"/remote-storages/#{remote_storage.id}")

      {:ok, conn} =
        lv
        |> form("#remote_storage_form", %{
          "remote_storage" => %{
            "url" => "https://example.com",
            "http_config" => %{
              "token" => "token"
            }
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/remote-storages")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Remote storage updated successfully"

      updated_dremote_storage = RemoteStorages.get!(remote_storage.id)
      assert updated_dremote_storage.name == "My original remote storage"
      assert updated_dremote_storage.url == "https://example.com"
      assert updated_dremote_storage.http_config.token == "token"
    end
  end
end
