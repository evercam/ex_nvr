defmodule ExNVRWeb.RecordingListLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, RecordingsFixtures}
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir
  @moduletag :device

  defp assert_recording_info(lv, html, device, recording) do
    assert html =~ "#{recording.id}"
    assert html =~ device.name

    expected_start_date =
      recording.start_date
      |> DateTime.shift_zone!(device.timezone)
      |> Calendar.strftime("%b %d, %Y %H:%M:%S")

    expected_end_date =
      recording.end_date
      |> DateTime.shift_zone!(device.timezone)
      |> Calendar.strftime("%b %d, %Y %H:%M:%S")

    assert html =~ "#{expected_start_date}"
    assert html =~ "#{expected_end_date}"

    assert lv
           |> element(~s{[id="recording-#{recording.id}-link"]})
           |> has_element?()
  end

  describe "Recording list page" do
    setup %{device: device} do
      %{
        recordings:
          Enum.map(1..10, fn idx ->
            recording_fixture(device,
              start_date: DateTime.add(~U(2023-09-12 00:00:00Z), idx * 100)
            )
          end)
      }
    end

    test "render recordings page", %{conn: conn, device: device, recordings: recordings} do
      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings?page_size=1")

      # check pagination
      assert lv
             |> element("a", "Previous")
             |> has_element?()

      assert lv
             |> element("a", "Next")
             |> has_element?()

      assert lv
             |> element("a", "1")
             |> has_element?()

      for page_label <- ["1", "2", "...", "4", "5", "6", "...", "9", "10"] do
        assert html =~ page_label
      end

      assert_recording_info(lv, html, device, List.last(recordings))
    end

    test "paginate through recordings", %{conn: conn, device: device, recordings: recordings} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings?page_size=1")

      html = element(lv, "a", "2") |> render_click(%{page_size: 1})

      for page_label <- ["1", "2", "...", "4", "5", "6", "...", "9", "10"] do
        assert html =~ page_label
      end

      # check recording
      recording = Enum.at(recordings, length(recordings) - 2)
      assert_recording_info(lv, html, device, recording)
    end

    test "download recording", %{conn: conn, recordings: recordings} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings")

      recording = List.first(recordings)

      {:error, redirect} =
        lv
        |> element(
          ~s|a[href="/api/devices/#{recording.device_id}/recordings/#{recording.filename}/blob"]|
        )
        |> render_click()

      assert {:redirect, %{to: path}} = redirect
      assert path == "/api/devices/#{recording.device_id}/recordings/#{recording.filename}/blob"
    end
  end
end
