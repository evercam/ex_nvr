defmodule ExNVRWeb.ExportFootageDatesLiveTest do
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}
  import Mimic
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir

  setup :set_mimic_global

  setup %{conn: conn} do
    stub(ExNVR.Disk, :list_drives!, fn -> [] end)
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp form_dates(html) do
    [start_date, end_date] =
      for id <- ["export_start_date", "export_end_date"] do
        [value] =
          html |> Floki.parse_document!() |> Floki.attribute("##{id}", "value")

        NaiveDateTime.from_iso8601!(value <> ":00")
      end

    {start_date, end_date}
  end

  defp assert_now_in(end_date, timezone) do
    now = timezone |> DateTime.now!() |> DateTime.to_naive()
    assert abs(NaiveDateTime.diff(now, end_date, :second)) < 120
  end

  test "defaults to the last 15 minutes in the device's timezone", %{
    conn: conn,
    tmp_dir: tmp_dir
  } do
    device = camera_device_fixture(tmp_dir, %{timezone: "Asia/Tokyo"})
    {:ok, _lv, html} = live(conn, ~p"/export-footage?device_id=#{device.id}")

    {start_date, end_date} = form_dates(html)
    assert NaiveDateTime.diff(end_date, start_date, :minute) == 15
    assert_now_in(end_date, "Asia/Tokyo")
  end

  test "untouched defaults follow the selected device's timezone", %{
    conn: conn,
    tmp_dir: tmp_dir
  } do
    camera_device_fixture(tmp_dir, %{timezone: "Asia/Tokyo"})
    other = camera_device_fixture(tmp_dir, %{timezone: "America/New_York"})
    {:ok, lv, html} = live(conn, ~p"/export-footage")
    {start_date, end_date} = form_dates(html)

    html =
      lv
      |> form("#export-form",
        export: %{
          "device_id" => other.id,
          "start_date" => Calendar.strftime(start_date, "%Y-%m-%dT%H:%M"),
          "end_date" => Calendar.strftime(end_date, "%Y-%m-%dT%H:%M")
        }
      )
      |> render_change()

    {_start_date, end_date} = form_dates(html)
    assert_now_in(end_date, "America/New_York")
  end

  test "keeps dates the user changed when switching device", %{conn: conn, tmp_dir: tmp_dir} do
    camera_device_fixture(tmp_dir, %{timezone: "Asia/Tokyo"})
    other = camera_device_fixture(tmp_dir, %{timezone: "America/New_York"})
    {:ok, lv, _html} = live(conn, ~p"/export-footage")

    html =
      lv
      |> form("#export-form",
        export: %{
          "device_id" => other.id,
          "start_date" => "2024-12-15T11:00",
          "end_date" => "2024-12-15T12:00"
        }
      )
      |> render_change()

    assert form_dates(html) == {~N[2024-12-15 11:00:00], ~N[2024-12-15 12:00:00]}
  end
end
