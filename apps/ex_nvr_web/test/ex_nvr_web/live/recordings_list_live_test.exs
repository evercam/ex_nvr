defmodule ExNVRWeb.RecordingListLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures, RecordingsFixtures}
  import Phoenix.LiveViewTest

  describe "Recording list page" do
    setup do
      device = device_fixture()

      %{device: device, recording: recording_fixture(device)}
    end

    test "render recordings page", %{conn: conn, device: device, recording: recording} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings")

      assert html =~ recording.id
      assert html =~ device.name
      assert html =~ recording.start_date
      assert html =~ recording.end_date
    end

    test "redirect if user is not logged in", %{conn: conn} do
      {:error, redirect} = live(conn, ~p"/recordings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/login"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
