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

        assert html =~ "#{DateTime.to_iso8601(recording.start_date, :extended, 0)}"
        assert html =~ "#{DateTime.to_iso8601(recording.end_date, :extended, 0)}"

        assert lv
        |> element("button", "Download")
        |> has_element?()
      end
    end

    test "download recording", %{conn: conn, device: device, recordings: recordings} do
        {:ok, lv, _html} =
          conn
          |> log_in_user(user_fixture())
          |> live(~p"/recordings")

        recording = List.first(recordings)
        form_id = "#"<>"#{recording.id}_form"
        form = lv
                |> form(form_id)

        conn = submit_form(form, conn)
        assert conn.method == "GET"
      end
  end
end
