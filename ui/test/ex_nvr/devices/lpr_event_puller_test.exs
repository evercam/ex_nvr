defmodule ExNVR.Devices.LPREventPullerTest do
  use ExNVR.DataCase

  alias ExNVR.Devices.LPREventPuller
  alias ExNVR.Events
  alias Plug.Conn

  import ExNVR.DevicesFixtures

  @lpr_plate_image "test/fixtures/images/license-plate.jpg"
  @moduletag :tmp_dir

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "pull lpr events from hik camera", %{bypass: bypass} = context do
    device =
      camera_device_fixture(context.tmp_dir, %{
        vendor: "HIKVISION",
        url: url(bypass.port)
      })

    Bypass.expect(
      bypass,
      "POST",
      "/ISAPI/Traffic/channels/1/vehicledetect/plates",
      fn conn ->
        conn
        |> Conn.put_resp_content_type("application/xml")
        |> Conn.resp(200, hik_response())
      end
    )

    event_plate = File.read!(@lpr_plate_image)

    Bypass.expect(bypass, "GET", "/doc/ui/images/plate/license-plate.jpg", fn conn ->
      conn
      |> Conn.put_resp_content_type("image/jpeg")
      |> Conn.resp(200, event_plate)
    end)

    assert {:ok, state} = LPREventPuller.init(device: device)
    assert {:noreply, state} = LPREventPuller.handle_info(:pull_events, state)

    assert DateTime.compare(state.last_event_timestamp, ~U[2024-04-28 13:00:00Z]) == :eq

    assert {:ok, {records, _}} = Events.list_lpr_events(%{}, include_plate_image: true)

    assert length(records) == 1
    lpr_event = Enum.at(records, 0)
    assert lpr_event.direction == :in
    assert lpr_event.capture_time == ~U[2024-04-28 13:00:00.000000Z]
    assert lpr_event.plate_number == "ABC1234"
    assert lpr_event.plate_image == Base.encode64(event_plate)
  end

  test "pull lpr events from milesight camera", %{bypass: bypass} = context do
    device =
      camera_device_fixture(context.tmp_dir, %{
        vendor: "Milesight Technology Co.,Ltd.",
        url: url(bypass.port)
      })

    Bypass.expect(
      bypass,
      "GET",
      "/cgi-bin/operator/operator.cgi",
      fn conn ->
        conn
        |> Conn.put_resp_content_type("text/html; charset=UTF-8")
        |> Conn.resp(200, milesight_response())
      end
    )

    event_plate = File.read!(@lpr_plate_image)

    Bypass.expect(bypass, "GET", "/LPR/license-plate.jpg", fn conn ->
      conn
      |> Conn.put_resp_content_type("image/jpeg")
      |> Conn.resp(200, event_plate)
    end)

    assert {:ok, state} = LPREventPuller.init(device: device)
    assert {:noreply, state} = LPREventPuller.handle_info(:pull_events, state)

    assert state.last_event_timestamp == ~U[2024-04-27 12:50:06.000000Z]

    assert {:ok, {records, _}} = Events.list_lpr_events(%{}, include_plate_image: true)

    assert length(records) == 1
    lpr_event = Enum.at(records, 0)
    assert lpr_event.direction == :away
    assert lpr_event.capture_time == ~U[2024-04-27 12:50:06.000000Z]
    assert lpr_event.plate_number == "ABC1234"
    assert lpr_event.plate_image == Base.encode64(event_plate)
  end

  test "pull lpr events from axis camera", %{bypass: bypass} = context do
    device =
      camera_device_fixture(context.tmp_dir, %{
        vendor: "AXIS",
        url: url(bypass.port)
      })

    Bypass.expect(
      bypass,
      "GET",
      "/local/fflprapp/search.cgi",
      fn conn ->
        conn
        |> Conn.put_resp_content_type("application/xml")
        |> Conn.resp(200, axis_response())
      end
    )

    event_plate = File.read!(@lpr_plate_image)

    Bypass.expect(bypass, "GET", "/local/fflprapp/tools.cgi", fn conn ->
      conn
      |> Conn.put_resp_content_type("image/jpeg")
      |> Conn.resp(200, event_plate)
    end)

    assert {:ok, state} = LPREventPuller.init(device: device)
    assert {:noreply, state} = LPREventPuller.handle_info(:pull_events, state)

    assert DateTime.compare(state.last_event_timestamp, ~U(2024-04-28 15:00:00Z)) == :eq

    assert {:ok, {records, _}} = Events.list_lpr_events(%{}, include_plate_image: true)

    assert length(records) == 1
    lpr_event = Enum.at(records, 0)
    assert lpr_event.direction == :unknown
    assert lpr_event.capture_time == ~U[2024-04-28 15:00:00.000000Z]
    assert lpr_event.plate_number == "ABC1234"
    assert lpr_event.plate_image == Base.encode64(event_plate)
  end

  defp url(port) do
    "http://localhost:#{port}"
  end

  defp hik_response() do
    """
    <Plates>
      <Plate>
        <captureTime>20240428T1300000000</captureTime>
        <plateNumber>ABC1234</plateNumber>
        <picName>license-plate</picName>
        <direction>forward</direction>
      </Plate>
    </Plates>
    """
  end

  defp milesight_response() do
    """
    time_0=2024-04-27 12:50:06
    plate_0=ABC1234
    path_0=license-plate.jpg
    region_0=DEU
    direction_0=2
    roi_id_0=1
    plate_left_0=356
    plate_top_0=546
    plate_right_0=590
    plate_bottom_0=614
    """
  end

  defp axis_response() do
    """
    <events>
    <event>
        <TS>1714316400000</TS>
        <MOD_TS>2024-04-28 13:00:00 GMT</MOD_TS>
        <LPR>ABC1234</LPR>
        <LP_BMP>tools.cgi?action=getImage&amp;name=license-plate.jpg</LP_BMP>
        <DIRECTION>0</DIRECTION>
    </event>
    </events>
    """
  end
end
