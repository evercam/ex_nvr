defmodule ExNVRWeb.RecordingListLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, RecordingsFixtures}
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir
  @moduletag :device

  describe "Recording list page" do
    setup %{device: device} do
      %{
        recordings: Enum.map(1..5, fn _ -> recording_fixture(device) end)
      }
    end

    test "render recordings page", %{conn: conn, device: device, recordings: recordings} do
      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings")

      assert lv
              |> element("a", "Previous")
              |> has_element?()
      assert lv
              |> element("a", "Next")
              |> has_element?()
      assert lv
              |> element("a", "1")
              |> has_element?()
      for recording <- recordings do
        assert html =~ "#{recording.id}"
        assert html =~ device.name

        expected_start_date = recording.start_date
                        |> DateTime.shift_zone!(device.timezone)
                        |> Calendar.strftime("%b %d, %Y %H:%M:%S")

        expected_end_date = recording.end_date
                        |> DateTime.shift_zone!(device.timezone)
                        |> Calendar.strftime("%b %d, %Y %H:%M:%S")

        assert html =~ "#{expected_start_date}"
        assert html =~ "#{expected_end_date}"

        assert lv
        |> element(~s{[id="recording-#{recording.id}-link"]})
        |> has_element?()
      end
    end

    test "download recording", %{conn: conn, recordings: recordings} do
        {:ok, lv, _html} =
          conn
          |> log_in_user(user_fixture())
          |> live(~p"/recordings")

        recording = List.first(recordings)
        assert true
      end
  end
end
