defmodule ExNvrWeb.DeviceDetailsLiveTest do
  use ExNVRWeb.ConnCase
  use Mimic

  import ExNVR.{AccountsFixtures, DevicesFixtures, RecordingsFixtures}
  import Phoenix.LiveViewTest

  alias ExNVR.Devices
  alias ExNVRWeb.ViewUtils

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

  describe "Details tab - Start/Stop recording" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, user_fixture())}
    end

    test "shows Stop button when device is recording", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :recording})

      {:ok, lv, _html} =
        conn |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "button", "Stop")
      refute has_element?(lv, "button", "Start")
    end

    test "shows Start button when device is stopped", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :stopped})

      {:ok, lv, _html} =
        conn |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "button", "Start")
      refute has_element?(lv, "button", "Stop")
    end

    test "clicking Stop updates state to stopped", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :recording})

      {:ok, lv, _html} =
        conn |> live(~p"/devices/#{device.id}/details")

      lv |> element("button", "Stop") |> render_click()

      assert has_element?(lv, "span.bg-yellow-100", "STOPPED")
      assert has_element?(lv, "button", "Start")
      assert Devices.get(device.id).state == :stopped
    end

    test "clicking Start updates state to recording", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :stopped})

      {:ok, lv, _html} =
        conn |> live(~p"/devices/#{device.id}/details")

      lv |> element("button", "Start") |> render_click()

      assert has_element?(lv, "span.bg-green-100", "RECORDING")
      assert has_element?(lv, "button", "Stop")
      assert Devices.get(device.id).state == :recording
    end
  end

  describe "Recordings tab" do
    setup %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir)

      recordings =
        Enum.map(1..3, fn idx ->
          recording_fixture(device,
            start_date: DateTime.add(~U(2023-09-12 00:00:00Z), idx * 100),
            end_date: DateTime.add(~U(2023-09-14 00:00:00Z), idx * 100)
          )
        end)

      %{device: device, recordings: recordings, conn: log_in_user(conn, user_fixture())}
    end

    test "renders recordings with duration column", %{
      conn: conn,
      device: device,
      recordings: recordings
    } do
      {:ok, lv, html} = live(conn, ~p"/devices/#{device.id}/details?tab=recordings")

      for recording <- recordings do
        assert html =~ "#{recording.id}"

        assert lv
               |> element(~s{[id="recording-#{recording.id}-link"]})
               |> has_element?()

        expected_duration =
          ViewUtils.humanize_duration(
            DateTime.diff(recording.end_date, recording.start_date, :millisecond)
          )

        assert html =~ expected_duration
      end
    end

    test "shows preview button for each recording", %{
      conn: conn,
      device: device,
      recordings: recordings
    } do
      {:ok, lv, _html} = live(conn, ~p"/devices/#{device.id}/details?tab=recordings")

      for recording <- recordings do
        assert lv |> element(~s{[id="thumbnail-#{recording.id}"]}) |> has_element?()
      end
    end

    test "video modal is initially hidden", %{conn: conn, device: device} do
      {:ok, lv, _html} = live(conn, ~p"/devices/#{device.id}/details?tab=recordings")

      assert lv |> element("#popup-container.hidden") |> has_element?()
    end

    test "video modal contains player, title and close button", %{conn: conn, device: device} do
      {:ok, lv, _html} = live(conn, ~p"/devices/#{device.id}/details?tab=recordings")

      assert lv |> element("#recording-modal-title") |> has_element?()
      assert lv |> element("#recording-player") |> has_element?()
      assert lv |> element("button[title='Close']") |> has_element?()
    end

    test "filter recordings by start date", %{
      conn: conn,
      device: device,
      recordings: recordings
    } do
      {:ok, lv, _html} = live(conn, ~p"/devices/#{device.id}/details?tab=recordings")

      result =
        lv
        |> form("#recording-filter-form", %{"filters[0][value]" => "2023-09-11T00:00"})
        |> render_change()

      for recording <- recordings do
        assert result =~ "#{recording.id}"
      end
    end

    test "filter recordings by start date with no results", %{conn: conn, device: device} do
      {:ok, lv, _html} = live(conn, ~p"/devices/#{device.id}/details?tab=recordings")

      result =
        lv
        |> form("#recording-filter-form", %{"filters[0][value]" => "2150-01-01T00:00"})
        |> render_change()

      assert result =~ "No results."
    end
  end

  describe "Details tab - PubSub device updates" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, user_fixture())}
    end

    test "status badge updates when device state changes via PubSub", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      device = camera_device_fixture(tmp_dir, %{state: :stopped})

      {:ok, lv, _html} =
        conn |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "span.bg-yellow-100", "STOPPED")

      {:ok, updated_device} = Devices.update_state(device, :recording)
      send(lv.pid, {:device_updated, updated_device})

      assert has_element?(lv, "span.bg-green-100", "RECORDING")
    end

    @tag :set_mimic_global
    test "snapshot player activates when device transitions from stopped to recording", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      stub(ExNVR.Devices, :fetch_snapshot, fn _device -> {:ok, @minimal_jpeg} end)

      device =
        camera_device_fixture(tmp_dir, %{
          state: :stopped,
          stream_config: %{snapshot_uri: "http://camera.local/snapshot.jpg"}
        })

      {:ok, lv, _html} =
        conn |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "p", "Device is stopped")
      refute has_element?(lv, "img[src^='data:image']")

      {:ok, updated_device} = Devices.update_state(device, :recording)
      send(lv.pid, {:device_updated, updated_device})
      send(lv.pid, :refresh_snapshot)

      assert has_element?(lv, "img[src^='data:image/jpeg;base64,']")
    end

    @tag :set_mimic_global
    test "snapshot player clears when device transitions from recording to stopped", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      stub(ExNVR.Devices, :fetch_snapshot, fn _device -> {:ok, @minimal_jpeg} end)

      device =
        camera_device_fixture(tmp_dir, %{
          state: :recording,
          stream_config: %{snapshot_uri: "http://camera.local/snapshot.jpg"}
        })

      {:ok, lv, _html} =
        conn |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "img[src^='data:image/jpeg;base64,']")

      {:ok, updated_device} = Devices.update_state(device, :stopped)
      send(lv.pid, {:device_updated, updated_device})

      refute has_element?(lv, "img[src^='data:image']")
      assert has_element?(lv, "p", "Device is stopped")
    end
  end
end
