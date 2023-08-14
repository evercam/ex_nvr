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
        recordings: Enum.map(1..500, fn _ -> recording_fixture(device) end)
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
      assert lv
              |> element("a", "2")
              |> has_element?()
      assert lv
              |> element("a", "3")
              |> has_element?()
      assert lv
              |> element("a", "4")
              |> has_element?()
      assert lv
              |> element("a", "5")
              |> has_element?()
      # for recording <- recordings do
      #   assert html =~ "#{recording.id}"
      #   assert html =~ device.name

      #   assert html =~ "#{DateTime.to_iso8601(recording.start_date, :extended, 0)}"
      #   assert html =~ "#{DateTime.to_iso8601(recording.end_date, :extended, 0)}"
      # end
    end
  end
end
