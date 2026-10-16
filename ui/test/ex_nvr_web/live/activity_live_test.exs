defmodule ExNVRWeb.ActivityLiveTest do
  use ExNVRWeb.ConnCase
  use Mimic

  import Phoenix.LiveViewTest
  import ExNVR.{AccountsFixtures, ActivityFixtures, DevicesFixtures, EventsFixtures}

  alias ExNVR.{Accounts, Activity}

  @moduletag :tmp_dir

  describe "Activity page" do
    setup %{conn: conn, tmp_dir: tmp_dir} do
      user = user_fixture(%{role: :user})
      device = camera_device_fixture(tmp_dir, %{name: "Test Camera"})

      {:ok, conn: log_in_user(conn, user), device: device}
    end

    test "opens the system tab by default", %{conn: conn, device: device} do
      {:ok, lv, html} = live(conn, ~p"/activity")

      assert html =~ "Activity"
      assert html =~ device.name

      assert has_element?(lv, "#tab-system[aria-selected=true]")
      assert has_element?(lv, "#events-list")
      refute has_element?(lv, "#user-activity")
    end

    test "is available to non admin users", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/activity?tab=user")
      assert has_element?(lv, "#user-activity")
    end

    test "switches between tabs", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/activity")

      lv |> element("#tab-user a") |> render_click()

      assert_patch(lv, ~p"/activity?tab=user")
      assert has_element?(lv, "#tab-user[aria-selected=true]")
      assert has_element?(lv, "#user-activity")
      refute has_element?(lv, "#events-list")

      lv |> element("#tab-system a") |> render_click()

      assert_patch(lv, ~p"/activity?tab=system")
      assert has_element?(lv, "#events-list")
    end

    test "the generic events page redirects to the system tab", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/events/generic?page=2")) ==
               ~p"/activity?page=2&tab=system"

      assert redirected_to(get(conn, ~p"/events/generic?tab=webhook")) ==
               ~p"/activity?tab=webhook"
    end
  end

  describe "System tab" do
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

      {:ok, conn: log_in_user(conn, user), device: device, events: [event1, event2]}
    end

    test "lists events and allows filtering", %{conn: conn, events: [event1, event2]} do
      {:ok, lv, _html} = live(conn, ~p"/activity")

      assert render(lv) =~ event1.type
      assert render(lv) =~ event2.type

      lv
      |> form("#fitlers-form", %{"filters[1][value]" => "motion_detected"})
      |> render_change()

      assert render(lv) =~ "motion_detected"
      refute render(lv) =~ "person_detected"
    end

    test "supports pagination", %{conn: conn, device: device} do
      Enum.each(1..20, fn i -> event_fixture("test_event_#{i}", device, %{}) end)

      {:ok, lv, _html} = live(conn, ~p"/activity")

      assert has_element?(lv, "[aria-label='Pagination']")

      lv |> element("a[phx-value-page='2']", "2") |> render_click()

      assert_patch(lv, ~p"/activity?page=2&tab=system")
    end
  end

  describe "User tab" do
    setup %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{name: "Front Gate"})
      now = DateTime.utc_now()

      login =
        entry_fixture(
          time: DateTime.add(now, -2, :minute),
          category: :auth,
          action: "auth.login_failed",
          severity: :warning,
          message: "Failed login for admin@localhost"
        )

      updated =
        entry_fixture(
          time: DateTime.add(now, -1, :minute),
          device: device,
          message: "Device Front Gate updated",
          metadata: %{
            changes: %{"name" => "Front Gate", "credentials.password" => "[REDACTED]"}
          }
        )

      deleted =
        entry_fixture(
          time: now,
          action: "device.deleted",
          message: "Device Old Cam deleted",
          device: %{id: Ecto.UUID.generate(), name: "Old Cam"}
        )

      %{
        conn: log_in_user(conn, user_fixture()),
        device: device,
        entries: [login, updated, deleted]
      }
    end

    test "lists entries", %{conn: conn, device: device} do
      {:ok, lv, html} = live(conn, ~p"/activity?tab=user")

      assert html =~ "Failed login for admin@localhost"
      assert html =~ "Device Front Gate updated"
      assert html =~ "Device Old Cam deleted"
      assert html =~ "tester@example.com"

      assert has_element?(lv, ~s|a[href="/devices/#{device.id}/details"]|, "Front Gate")
      assert has_element?(lv, "span[title='Device deleted']", "Old Cam")
    end

    test "shows the new values of changes only", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/activity?tab=user")

      details = lv |> element("#activity-entries details") |> render()
      assert details =~ "credentials.password"
      assert details =~ "changed"
      refute details =~ "[REDACTED]"
    end

    test "filters entries with quick filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/activity?tab=user")

      lv |> element("#quick-filter-alerts") |> render_click()

      html = render(lv)
      assert html =~ "Failed login for admin@localhost"
      refute html =~ "Device Front Gate updated"
      assert has_element?(lv, "#quick-filter-alerts.bg-blue-600")
    end

    test "filters entries with the filter form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/activity?tab=user")

      lv
      |> form("#activity-filter-form", %{"filters" => %{"3" => %{"value" => "Old Cam"}}})
      |> render_change()

      html = render(lv)
      assert html =~ "Device Old Cam deleted"
      refute html =~ "Failed login for admin@localhost"
    end

    test "shows new entries live", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/activity?tab=user")

      :ok = Activity.log(valid_entry_attributes(action: "auth.logout", message: "Bye"))
      # The LiveView forwards new entries to the tab with `send_update/2`.
      :sys.get_state(lv.pid)

      assert render(lv) =~ "auth.logout"
    end

    test "counts new entries when filtered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/activity?tab=user")
      lv |> element("#quick-filter-logins") |> render_click()

      :ok = Activity.log(valid_entry_attributes(action: "export.started", category: :export))
      :sys.get_state(lv.pid)

      assert has_element?(lv, "#activity-new-entries", "1 new entry")
      refute render(lv) =~ "export.started"

      lv |> element("#activity-new-entries") |> render_click()
      refute has_element?(lv, "#activity-new-entries")
    end
  end

  describe "Webhook settings" do
    setup %{conn: conn, tmp_dir: tmp_dir} do
      Mimic.copy(ExNVRWeb.Endpoint)
      Mimic.stub(ExNVRWeb.Endpoint, :local_url, fn -> "http://localhost:4002" end)

      user = user_fixture()
      device = camera_device_fixture(tmp_dir, %{name: "Test Camera"})

      {:ok, conn: log_in_user(conn, user), user: user, device: device}
    end

    test "open from the system tab", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/activity")
      refute has_element?(lv, "#webhook-config")

      lv |> element("#open-webhook-settings") |> render_click()
      assert has_element?(lv, "#webhook-settings #webhook-config")

      render_hook(lv, "close_webhook_settings", %{})
      refute has_element?(lv, "#webhook-config")
    end

    test "open from the old webhook tab link", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/activity?tab=webhook")

      assert has_element?(lv, "#tab-system[aria-selected=true]")
      assert has_element?(lv, "#webhook-config")
    end

    test "generates token", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/activity?tab=webhook")

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

      {:ok, lv, _html} = live(conn, ~p"/activity?tab=webhook")

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

      {:ok, lv, _html} = live(conn, ~p"/activity?tab=webhook")

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

      {:ok, lv, _html} = live(conn, ~p"/activity?tab=webhook")

      type = "custom_event"

      updated =
        lv
        |> form("#endpoint-form", %{
          "device_id" => device.id,
          "type" => type
        })
        |> render_change()

      expected_url = "http://localhost:4002/api/devices/#{device.id}/events?type=#{type}"

      assert updated =~ expected_url
    end
  end
end
