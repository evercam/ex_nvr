defmodule ExNVRWeb.RecordingListLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, RecordingsFixtures}
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir
  @moduletag :device

  describe "Recording list page" do
    setup %{device: device} do
      %{recording: recording_fixture(device)}
    end

    test "render recordings page", %{conn: conn, device: device, recording: recording} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings")

      assert html =~ "#{recording.id}"
      assert html =~ device.name

      assert html =~ "#{DateTime.to_iso8601(recording.start_date, :extended, 0)}"
      assert html =~ "#{DateTime.to_iso8601(recording.end_date, :extended, 0)}"
    end

    test "redirect if user is not logged in", %{conn: conn} do
      {:error, redirect} = live(conn, ~p"/recordings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/login"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
