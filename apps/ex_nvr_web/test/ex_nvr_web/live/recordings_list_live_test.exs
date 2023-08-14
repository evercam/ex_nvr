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
  end
end
