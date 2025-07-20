defmodule ExNVRWeb.GenericEventsLiveTest do
  use ExNVRWeb.ConnCase

  import Phoenix.LiveViewTest
  import ExNVR.{AccountsFixtures, DevicesFixtures, EventsFixtures}

  alias ExNVR.Accounts

  @moduletag :tmp_dir

  describe "Generic Events page" do
    setup %{conn: conn, tmp_dir: tmp_dir} do
      user = user_fixture()
      device = camera_device_fixture(tmp_dir, %{name: "Test Camera"})

      {:ok, event1} =
        event_fixture("motion_detected", device, %{
          time: DateTime.utc_now() |> DateTime.add(-1, :hour),
          metadata: %{"confidence" => 0.85}
        })

      {:ok, event2} =
        event_fixture("person_detected", device, %{
          time: DateTime.utc_now(),
          metadata: %{"confidence" => 0.92}
        })

      {:ok, conn: log_in_user(conn, user), user: user, device: device, events: [event1, event2]}
    end

    test "renders default tab (events) on initial load", %{conn: conn, device: device} do
      {:ok, lv, html} = live(conn, ~p"/events/generic")

      assert html =~ "Generic Events"
      assert html =~ device.name

      assert has_element?(lv, "#tab-events[aria-selected=true]")
      assert has_element?(lv, "#events-list")
      refute has_element?(lv, "#webhook-config[aria-selected=true]")
    end

    test "can switch between tabs", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/events/generic")

      assert has_element?(lv, "#tab-events[aria-selected=true]")

      lv |> element("#tab-webhook a") |> render_click()

      assert_patch(lv, ~p"/events/generic?tab=webhook")
      assert has_element?(lv, "#tab-webhook[aria-selected=true]")
      assert has_element?(lv, "#webhook-config")
      refute has_element?(lv, "#tab-events[aria-selected=true]")

      lv |> element("#tab-events a") |> render_click()

      assert_patch(lv, ~p"/events/generic?tab=events")
      assert has_element?(lv, "#tab-events[aria-selected=true]")
      assert has_element?(lv, "#events-list")
    end

    test "can navigate directly to a specific tab via URL", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/events/generic?tab=webhook")

      assert has_element?(lv, "#tab-webhook[aria-selected=true]")
      assert has_element?(lv, "#webhook-config")
    end

    test "events list displays events and allows filtering", %{
      conn: conn,
      events: [event1, event2]
    } do
      {:ok, lv, _html} = live(conn, ~p"/events/generic")

      assert has_element?(lv, "#events-list")
      assert render(lv) =~ event1.type
      assert render(lv) =~ event2.type

      lv
      |> form("#fitlers-form", %{"filters[1][value]" => "motion_detected"})
      |> render_change()

      assert render(lv) =~ "motion_detected"
      refute render(lv) =~ "person_detected"
    end

    test "events list supports pagination", %{conn: conn, device: device} do
      Enum.each(1..20, fn i ->
        event_fixture("test_event_#{i}", device, %{})
      end)

      {:ok, lv, _html} = live(conn, ~p"/events/generic")

      assert has_element?(lv, "[aria-label='Pagination']")

      lv |> element("a[phx-value-page='2']", "2") |> render_click()

      assert_patch(lv, ~p"/events/generic?page=2")
    end
  end

  describe "Webhook Config functionality" do
    setup %{conn: conn, tmp_dir: tmp_dir} do
      user = user_fixture()
      device = camera_device_fixture(tmp_dir, %{name: "Test Camera"})
      {:ok, conn: log_in_user(conn, user), user: user, device: device}
    end

    test "generates token", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/events/generic?tab=webhook")

      lv
      |> element("button", "Generate Token")
      |> render_click()

      assert Accounts.get_webhook_token(user)

      refute lv
             |> element("button[phx-click='generate_token']")
             |> has_element?()

      assert lv
             |> element("button[phx-click='delete_token']")
             |> has_element?()
    end

    test "deletes token", %{conn: conn, user: user} do
      Accounts.generate_webhook_token(user)

      {:ok, lv, _html} = live(conn, ~p"/events/generic?tab=webhook")

      lv
      |> element("button[phx-click='delete_token']")
      |> render_click()

      refute Accounts.get_webhook_token(user)

      assert lv
             |> element("button[phx-click='generate_token']")
             |> has_element?()

      refute lv
             |> element("button[phx-click='delete_token']")
             |> has_element?()
    end

    test "toggle token visibility", %{conn: conn, user: user} do
      token = Accounts.generate_webhook_token(user)

      {:ok, lv, _html} = live(conn, ~p"/events/generic?tab=webhook")

      assert lv |> element("#wh-token") |> render() =~ "•••••••"
      refute lv |> element("#wh-token") |> render() =~ token
      assert lv |> has_element?("button[title='Show token']")

      lv |> element("button[title='Show token']") |> render_click()
      assert lv |> element("#wh-token") |> render() =~ token
      refute lv |> element("#wh-token") |> render() =~ "•••••••"
      assert lv |> has_element?("button[title='Hide token']")
    end

    test "updates the webhook url based on the device_id and type", %{
      conn: conn,
      device: device,
      user: user
    } do
      Accounts.generate_webhook_token(user)

      {:ok, lv, _html} = live(conn, ~p"/events/generic?tab=webhook")

      type = "custom_event"

      updated =
        lv
        |> form("#endpoint-form", %{
          "device_id" => device.id,
          "type" => type
        })
        |> render_change()

      expected_url =
        "#{ExNVRWeb.Endpoint.local_url()}/api/devices/#{device.id}/events?type=#{type}"

      assert updated =~ expected_url
    end
  end
end
