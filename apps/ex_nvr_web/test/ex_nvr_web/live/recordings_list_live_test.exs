defmodule ExNVRWeb.RecordingListLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, RecordingsFixtures}
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir
  @moduletag devices: 3

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
    setup %{devices: devices} do
      [first_device, second_device, third_device] = devices

      %{
        device: first_device,
        recordings:
          Enum.map(1..10, fn idx ->
            recording_fixture(first_device,
              start_date: DateTime.add(~U(2023-09-12 00:00:00Z), idx * 100)
            )
          end),
        second_device: second_device,
        second_recordings:
          Enum.map(1..5, fn idx ->
            recording_fixture(second_device,
              start_date: DateTime.add(~U(2023-09-11 00:00:00Z), idx * 100)
            )
          end),
        third_device: third_device
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
      second_device: new_device,
      second_recordings: new_recordings
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

      for recording <- new_recordings,
          do: assert_recording_info(lv, result, new_device, recording)
    end

    test "Filter recordings by non-existing device", %{conn: conn, third_device: third_device} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings")

      result =
        lv
        |> form("#recording-filter-form", %{
          "filters[0][value]" => "#{third_device.id}"
        })
        |> render_change()

      assert result =~ "0"
      assert result =~ "No results."
    end

    test "Filter recordings by start date and end date", %{
      conn: conn,
      recordings: recordings,
      device: device
    } do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/recordings")

      result =
        lv
        |> form("#recording-filter-form", %{
          "filters[1][value]" => ~U(2023-09-12 00:00:00Z),
          "filters[2][value]" => ~U(2024-09-12 00:00:00Z)
        })
        |> render_change()

      assert result =~ "phx-click=\"nav\" phx-value-page=\"1\" "

      for recording <- recordings, do: assert_recording_info(lv, result, device, recording)
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

      assert result =~ "phx-click=\"nav\" phx-value-page=\"0\" "
      assert result =~ "No results."
    end

    test "Sort recordings by Device Name", %{
      conn: conn,
      device: device,
      second_device: second_device,
      second_recordings: second_recordings,
      recordings: recordings
    } do
      {latest_recording, asc_device} =
        cond do
          device.name > second_device.name -> {List.last(second_recordings), second_device}
          device.name < second_device.name -> {List.last(recordings), device}
          true -> {List.last(recordings), device}
        end

      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(
          ~p"/recordings?page_size=1&order_by[]=device_name&order_by[]=start_date&order_by[]=end_date&order_directions[]=asc&order_directions[]=desc"
        )

      assert_recording_info(lv, html, asc_device, latest_recording)
    end

    test "Sort recordings by Start Date (ASC)", %{
      conn: conn,
      device: device,
      second_device: second_device,
      second_recordings: second_recordings,
      recordings: recordings
    } do
      first_new_recording = List.first(second_recordings)
      first_old_recording = List.first(recordings)

      {earliest_recording, device_obj} =
        cond do
          first_new_recording.start_date == first_old_recording.start_date ->
            if device.name < second_device.name,
              do: {first_old_recording, device},
              else: {first_new_recording, second_device}

          first_new_recording.start_date > first_old_recording.start_date ->
            {first_old_recording, device}

          first_new_recording.start_date < first_old_recording.start_date ->
            {first_new_recording, second_device}

          true ->
            {first_new_recording, second_device}
        end

      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(
          ~p"/recordings?page_size=1&order_by[]=start_date&order_by[]=device_name&order_directions[]=asc&order_directions[]=asc"
        )

      assert_recording_info(lv, html, device_obj, earliest_recording)
    end

    test "Sort recordings by End Date (DESC)", %{
      conn: conn,
      device: device,
      recordings: recordings,
      second_device: second_device,
      second_recordings: second_recordings
    } do
      first_new_recording =
        Enum.sort(second_recordings, fn r1, r2 ->
          case DateTime.compare(r1.end_date, r2.end_date) do
            :gt -> true
            _ -> false
          end
        end)
        |> List.first()

      first_old_recording =
        Enum.sort(recordings, fn r1, r2 ->
          case DateTime.compare(r1.end_date, r2.end_date) do
            :gt -> true
            _ -> false
          end
        end)
        |> List.first()

      {recording, device_obj} =
        cond do
          first_new_recording.end_date > first_old_recording.end_date ->
            {first_new_recording, second_device}

          first_new_recording.end_date < first_old_recording.end_date ->
            {first_old_recording, device}

          first_new_recording.end_date == first_old_recording.end_date ->
            if device.name > second_device.name,
              do: {first_old_recording, device},
              else: {first_new_recording, second_device}

          true ->
            {first_old_recording, device}
        end

      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(
          ~p"/recordings?page_size=1&order_by[]=end_date&order_by[]=device_name&order_directions[]=desc&order_directions[]=desc"
        )

      assert_recording_info(lv, html, device_obj, recording)
    end
  end
end
