defmodule ExNVRWeb.RecordingListLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, RecordingsFixtures, DevicesFixtures}
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir
  @moduletag :device

  defp refute_recording_info(lv, recording) do
    refute lv
           |> element(~s{[id="recording-#{recording.id}-link"]})
           |> has_element?()
  end

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
    setup %{device: device, tmp_dir: tmp_dir} do
      new_device = camera_device_fixture(tmp_dir, %{name: "Device_yxz"})

      %{
        recordings:
          Enum.map(1..10, fn idx ->
            recording_fixture(device,
              start_date: DateTime.add(~U(2023-09-12 00:00:00Z), idx * 100),
              end_date: DateTime.add(~U(2023-09-14 00:00:00Z), idx * 100)
            )
          end),
        new_device: new_device,
        new_recordings:
          Enum.map(1..5, fn idx ->
            recording_fixture(new_device,
              start_date: DateTime.add(~U(2023-09-01 00:00:00Z), idx * 100),
              end_date: DateTime.add(~U(2024-09-01 00:00:00Z), idx * 100)
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

    test "Filter recordings by device", %{
      conn: conn,
      recordings: recordings,
      new_device: new_device,
      new_recordings: new_recordings
    } do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings")

      result =
        lv
        |> form("#recording-filter-form", %{
          "filters[0][value]" => "#{new_device.id}"
        })
        |> render_change()

      assert result =~ "1"

      for new_recording <- new_recordings,
          do: assert_recording_info(lv, result, new_device, new_recording)

      for recording <- recordings,
          do: refute_recording_info(lv, recording)
    end

    test "Filter recordings by device with no recordings", %{conn: conn, tmp_dir: tmp_dir} do
      new_device = camera_device_fixture(tmp_dir)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings")

      result =
        lv
        |> form("#recording-filter-form", %{
          "filters[0][value]" => "#{new_device.id}"
        })
        |> render_change()

      assert result =~ "0"
      assert result =~ "No results."
    end

    test "Filter recordings by start date and end date", %{
      conn: conn,
      new_recordings: new_recordings,
      recordings: recordings,
      device: device
    } do
      logged_in_conn =
        conn
        |> log_in_user(user_fixture())

      {:ok, lv, _html} =
        logged_in_conn
        |> live(~p"/recordings")

      result =
        lv
        |> form("#recording-filter-form", %{
          "filters[1][value]" => ~U(2023-09-12 00:00:00Z)
        })
        |> render_change()

      for recording <- recordings, do: assert_recording_info(lv, result, device, recording)
      for new_recording <- new_recordings, do: refute_recording_info(lv, new_recording)

      # Filter by End Date
      {:ok, lv, _html} =
        logged_in_conn
        |> live(~p"/recordings")

      result =
        lv
        |> form("#recording-filter-form", %{
          "filters[2][value]" => ~U(2023-09-16 00:00:00Z)
        })
        |> render_change()

      for recording <- recordings, do: assert_recording_info(lv, result, device, recording)
      for new_recording <- new_recordings, do: refute_recording_info(lv, new_recording)
    end

    test "Filter recordings by start date and end date (No results)", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings")

      result =
        lv
        |> form("#recording-filter-form", %{
          "filters[1][value]" => ~U(2150-09-12 00:00:00Z),
          "filters[2][value]" => ~U(2023-09-11 00:00:00Z)
        })
        |> render_change()

      refute result =~ "phx-click=\"nav\" phx-value-page=\"0\" "
      assert result =~ "No results."
    end

    test "Sort recordings by Device Name, Start Date and End Date", %{
      conn: conn,
      device: device,
      recordings: recordings,
      new_device: new_device,
      new_recordings: new_recordings
    } do
      logged_in_conn =
        conn
        |> log_in_user(user_fixture())

      # Sort by Device Name ASC
      {:ok, lv, html} =
        logged_in_conn
        |> live(
          ~p"/recordings?page_size=1&order_by[]=device_name&order_by[]=start_date&order_by[]=end_date&order_directions[]=asc&order_directions[]=desc"
        )

      assert_recording_info(lv, html, device, List.last(recordings))

      # Sort by Start date ASC
      {:ok, lv, html} =
        logged_in_conn
        |> live(
          ~p"/recordings?page_size=1&order_by[]=start_date&order_by[]=device_name&order_directions[]=asc&order_directions[]=asc"
        )

      assert_recording_info(lv, html, new_device, List.first(new_recordings))

      # Sort by End date DESC
      {:ok, lv, html} =
        logged_in_conn
        |> live(
          ~p"/recordings?page_size=1&order_by[]=end_date&order_by[]=device_name&order_directions[]=desc&order_directions[]=desc"
        )

      assert_recording_info(lv, html, new_device, List.last(new_recordings))
    end

    test "Real time refresh of recording list", %{
      conn: conn,
      device: device
    } do
      logged_in_conn =
        conn
        |> log_in_user(user_fixture())

      {:ok, lv, _html} =
        logged_in_conn
        |> live(~p"/recordings")

      recording =
        recording_fixture(device,
          start_date: ~U(2023-09-12 00:00:00Z),
          end_date: ~U(2023-09-14 00:00:00Z)
        )

      html = render(lv)

      assert_recording_info(lv, html, device, recording)
    end
  end
end
