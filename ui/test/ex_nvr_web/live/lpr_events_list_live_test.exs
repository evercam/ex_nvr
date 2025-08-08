defmodule ExNVRWeb.LprEventsListLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, EventsFixtures, DevicesFixtures}
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir
  @moduletag :device

  defp refute_event_info(html, device, event) do
    expected_capture_time =
      event.capture_time
      |> DateTime.shift_zone!(device.timezone)
      |> Calendar.strftime("%b %d, %Y %H:%M:%S")

    refute html =~ "#{expected_capture_time}"
  end

  defp assert_event_info(html, device, event) do
    assert html =~ "#{event.id}"
    assert html =~ device.name

    expected_capture_time =
      event.capture_time
      |> DateTime.shift_zone!(device.timezone)
      |> Calendar.strftime("%b %d, %Y %H:%M:%S")

    assert html =~ "#{expected_capture_time}"
  end

  describe "LPR events list page" do
    setup %{device: device, tmp_dir: tmp_dir} do
      new_device = camera_device_fixture(tmp_dir, %{name: "Device_yxz"})

      %{
        events:
          Enum.map(1..10, fn idx ->
            event_fixture(:lpr, device,
              capture_time: DateTime.add(~U(2023-09-12 00:00:00Z), idx * 100)
            )
          end),
        new_device: new_device,
        new_events:
          Enum.map(1..5, fn idx ->
            event_fixture(:lpr, new_device,
              capture_time: DateTime.add(~U(2023-09-01 00:00:00Z), idx * 100)
            )
          end)
      }
    end

    test "render events page", %{conn: conn, device: device, events: events} do
      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/events/lpr?page_size=1")

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

      assert_event_info(html, device, List.last(events))
    end

    test "paginate through events", %{conn: conn, device: device, events: events} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/events/lpr?page_size=1")

      html = element(lv, "a", "2") |> render_click(%{page_size: 1})

      for page_label <- ["1", "2", "...", "4", "5", "6", "...", "9", "10"] do
        assert html =~ page_label
      end

      # check event
      event = Enum.at(events, length(events) - 2)
      assert_event_info(html, device, event)
    end

    test "Filter events by device", %{
      conn: conn,
      device: device,
      events: events,
      new_device: new_device,
      new_events: new_events
    } do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/events/lpr")

      result =
        lv
        |> form("#lpr-event-filter-form", %{
          "filters[0][value]" => "#{new_device.id}"
        })
        |> render_change()

      assert result =~ "1"

      for new_event <- new_events,
          do: assert_event_info(result, new_device, new_event)

      for event <- events,
          do: refute_event_info(result, device, event)
    end

    test "Filter events by device with no events", %{conn: conn, tmp_dir: tmp_dir} do
      new_device = camera_device_fixture(tmp_dir)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/events/lpr")

      result =
        lv
        |> form("#lpr-event-filter-form", %{
          "filters[0][value]" => "#{new_device.id}"
        })
        |> render_change()

      assert result =~ "0"
      assert result =~ "No results."
    end

    test "Filter recordings by capture time", %{
      conn: conn,
      new_events: new_events,
      events: events,
      device: device,
      new_device: new_device
    } do
      logged_in_conn =
        conn
        |> log_in_user(user_fixture())

      {:ok, lv, _html} =
        logged_in_conn
        |> live(~p"/events/lpr")

      result =
        lv
        |> form("#lpr-event-filter-form", %{
          "filters[1][value]" => ~U(2023-09-12 00:00:00Z)
        })
        |> render_change()

      for event <- events, do: assert_event_info(result, device, event)
      for new_event <- new_events, do: refute_event_info(result, new_device, new_event)

      {:ok, lv, _html} =
        logged_in_conn
        |> live(~p"/events/lpr")

      result =
        lv
        |> form("#lpr-event-filter-form", %{
          "filters[2][value]" => ~U(2023-09-12 00:00:00Z)
        })
        |> render_change()

      for event <- events, do: refute_event_info(result, device, event)
      for new_event <- new_events, do: assert_event_info(result, new_device, new_event)
    end
  end
end
