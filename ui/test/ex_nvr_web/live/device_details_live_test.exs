defmodule ExNvrWeb.DeviceDetailsLiveTest do
  use ExNVRWeb.ConnCase
  use Mimic

  import ExNVR.AccountsFixtures
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir

  # Minimal valid JPEG bytes (SOI + EOI markers)
  @minimal_jpeg <<0xFF, 0xD8, 0xFF, 0xD9>>

  describe "Device details page" do
    setup ctx do
      %{
        device: camera_device_fixture(ctx.tmp_dir),
        tabs: ["details", "recordings", "stats", "settings", "events"]
      }
    end

    test "render device details page", %{conn: conn, device: device, tabs: tabs} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "h2", "Device: #{device.name}")

      for tab <- tabs do
        assert lv |> element(~s|[id="tab-#{tab}"]|) |> has_element?()
      end
    end

    test "Changing tabs by clicking on tabs", %{conn: conn, device: device, tabs: tabs} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      for tab <- tabs do
        element = element(lv, "[phx-click='switch_tab'][phx-value-tab='#{tab}']")
        assert has_element?(element)

        _html = render_click(element)

        assert element(lv, "#tab-#{tab}[aria-selected='true']") |> has_element?()
      end
    end
  end

  describe "Details tab - General card" do
    test "renders device name, type, timezone and created at", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "dd", device.name)
      assert has_element?(lv, "dd", String.upcase(to_string(device.type)))
      assert has_element?(lv, "dd", device.timezone)
      assert has_element?(lv, "dt", "Created At")
    end

    test "shows recording status badge with green styling", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :recording})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "span.bg-green-100", "RECORDING")
    end

    test "shows failed status badge with red styling", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :failed})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "span.bg-red-100", "FAILED")
    end

    test "shows stopped status badge with yellow styling", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :stopped})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "span.bg-yellow-100", "STOPPED")
    end

    test "shows streaming status badge with green styling", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :streaming})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "span.bg-green-100", "STREAMING")
    end
  end

  describe "Details tab - Hardware card" do
    test "does not render when no hardware fields are set", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      refute has_element?(lv, "dt", "Vendor")
      refute has_element?(lv, "dt", "Model")
      refute has_element?(lv, "dt", "MAC Address")
      refute has_element?(lv, "dt", "URL")
    end

    test "renders vendor, model and mac when present", %{conn: conn, tmp_dir: tmp_dir} do
      device =
        camera_device_fixture(tmp_dir, %{
          vendor: "Hikvision",
          model: "DS-2CD2143G2-I",
          mac: "AA:BB:CC:DD:EE:FF"
        })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "dt", "Vendor")
      assert has_element?(lv, "dd", "Hikvision")
      assert has_element?(lv, "dt", "Model")
      assert has_element?(lv, "dd", "DS-2CD2143G2-I")
      assert has_element?(lv, "dt", "MAC Address")
      assert has_element?(lv, "dd", "AA:BB:CC:DD:EE:FF")
    end

    test "renders only fields that are present", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{vendor: "Axis"})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "dd", "Axis")
      refute has_element?(lv, "dt", "Model")
      refute has_element?(lv, "dt", "MAC Address")
    end
  end

  describe "Details tab - Snapshot player" do
    test "shows disabled placeholder when no snapshot URI is configured", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      device = camera_device_fixture(tmp_dir)

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "p", "No snapshot URL configured")
      assert has_element?(lv, "span", "Unavailable")
      refute has_element?(lv, "img[src^='data:image']")
    end

    test "shows 'Device is stopped' when state is stopped and snapshot URI is set", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      device =
        camera_device_fixture(tmp_dir, %{
          state: :stopped,
          stream_config: %{snapshot_uri: "http://camera.local/snapshot.jpg"}
        })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "p", "Device is stopped")
      assert has_element?(lv, "p", "Start the device to view snapshots")
      assert has_element?(lv, "span", "Stopped")
      refute has_element?(lv, "img[src^='data:image']")
    end

    test "shows 'Device connection failed' when state is failed and snapshot URI is set", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      device =
        camera_device_fixture(tmp_dir, %{
          state: :failed,
          stream_config: %{snapshot_uri: "http://camera.local/snapshot.jpg"}
        })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "p", "Device connection failed")
      assert has_element?(lv, "p", "Check device settings and connectivity")
      assert has_element?(lv, "span", "Failed")
      refute has_element?(lv, "img[src^='data:image']")
    end

    @tag :set_mimic_global
    test "shows loading spinner before first snapshot arrives", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      stub(ExNVR.Devices, :fetch_snapshot, fn _device -> {:error, :timeout} end)

      device =
        camera_device_fixture(tmp_dir, %{
          stream_config: %{snapshot_uri: "http://camera.local/snapshot.jpg"}
        })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "div.animate-spin")
      refute has_element?(lv, "img[src^='data:image']")
    end

    @tag :set_mimic_global
    test "shows snapshot image delivered over WebSocket when fetch succeeds", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      stub(ExNVR.Devices, :fetch_snapshot, fn _device -> {:ok, @minimal_jpeg} end)

      device =
        camera_device_fixture(tmp_dir, %{
          stream_config: %{snapshot_uri: "http://camera.local/snapshot.jpg"}
        })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "img[src^='data:image/jpeg;base64,']")
      assert has_element?(lv, "p", "Refreshes every 10 seconds")
      refute has_element?(lv, "div.animate-spin")
    end

    @tag :set_mimic_global
    test "keeps last successful snapshot when refresh fails", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      stub(ExNVR.Devices, :fetch_snapshot, fn _device -> {:ok, @minimal_jpeg} end)

      device =
        camera_device_fixture(tmp_dir, %{
          stream_config: %{snapshot_uri: "http://camera.local/snapshot.jpg"}
        })

      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "img[src^='data:image/jpeg;base64,']")

      stub(ExNVR.Devices, :fetch_snapshot, fn _device -> {:error, :econnrefused} end)
      send(lv.pid, :refresh_snapshot)

      # Previous snapshot should still be displayed
      assert has_element?(lv, "img[src^='data:image/jpeg;base64,']")
    end
  end
end
