defmodule ExNVRWeb.ExportFootageS3LiveTest do
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures, RemoteStoragesFixtures}
  import Mimic
  import Phoenix.LiveViewTest

  alias ExNVR.Export
  alias ExNVR.Export.S3

  @moduletag :tmp_dir

  setup :set_mimic_global

  setup %{conn: conn, tmp_dir: tmp_dir} do
    stub(ExNVR.Disk, :list_drives!, fn -> [] end)

    %{
      conn: log_in_user(conn, user_fixture()),
      device:
        camera_device_fixture(tmp_dir, %{
          stream_config: %{
            stream_uri: "rtsp://localhost:554/main",
            sub_stream_uri: "rtsp://localhost:554/sub"
          },
          storage_config: %{record_sub_stream: :always}
        }),
      remote_storage: remote_storage_fixture(%{s3_config: s3_config(%{kit_id: "kit-1"})})
    }
  end

  defp s3_config(attrs) do
    Map.merge(
      %{bucket: "test-bucket", region: "us-east-1", access_key_id: "a", secret_access_key: "s"},
      attrs
    )
  end

  defp s3_params(device, remote_storage, attrs \\ %{}) do
    Map.merge(
      %{
        "device_id" => device.id,
        "start_date" => "2024-12-15T11:00",
        "end_date" => "2024-12-15T12:00",
        "destination" => "s3",
        "remote_storage_id" => remote_storage.id,
        "stream" => "low",
        "camera_id" => "cam-exid"
      },
      attrs
    )
  end

  test "shows S3 options when S3 is selected", %{conn: conn, device: device} do
    {:ok, lv, html} = live(conn, ~p"/export-footage")
    refute html =~ "S3 storage"

    html =
      lv
      |> form("#export-form", export: %{"device_id" => device.id, "destination" => "s3"})
      |> render_change()

    assert html =~ "S3 storage"
    assert html =~ "Camera ID"
  end

  test "starts an S3 export job", %{conn: conn, device: device, remote_storage: remote_storage} do
    {:ok, lv, _html} = live(conn, ~p"/export-footage")
    params = s3_params(device, remote_storage)

    select_s3(lv, device)
    lv |> form("#export-form", export: params) |> render_change()
    assert lv |> form("#export-form", export: params) |> render_submit() =~ "Export started"

    {:ok, job} =
      S3.job(
        device,
        remote_storage,
        :low,
        "cam-exid",
        ~U(2024-12-15T11:00:00Z),
        ~U(2024-12-15T12:00:00Z)
      )

    # no recordings in range, so the job fails right away without touching S3
    wait_until(fn -> match?({:ok, %{status: :failed}}, Export.progress(job.dest_dir)) end)

    assert {:ok, manifest} = Export.Manifest.load(job.dest_dir)
    assert manifest.stream == :low
    assert manifest.split == :hourly
    assert manifest.destination.camera_id == "cam-exid"
    assert manifest.destination.kit_id == "kit-1"
  end

  test "flags skipped and overwritten files once completed", %{
    conn: conn,
    device: device,
    remote_storage: remote_storage
  } do
    start_date = ~U(2024-12-15T11:00:00Z)
    end_date = ~U(2024-12-15T12:00:00Z)
    {:ok, job} = S3.job(device, remote_storage, :low, "cam-exid", start_date, end_date)
    File.mkdir_p!(job.dest_dir)

    file = fn key, status, extra ->
      Map.merge(
        %{
          filename: "export.mp4",
          start_date: start_date,
          end_date: end_date,
          size: 2048,
          key: key,
          upload_status: status
        },
        extra
      )
    end

    %{
      device_id: device.id,
      stream: :low,
      start_date: start_date,
      end_date: end_date,
      split: :hourly,
      timezone: device.timezone,
      destination: job.destination
    }
    |> Export.Manifest.new()
    |> Map.merge(%{
      status: :completed,
      files: [
        file.("k/c/11/00_00.mp4", :uploaded, %{}),
        file.("k/c/12/00_00.mp4", :skipped, %{}),
        file.("k/c/13/00_00.mp4", :overwritten, %{previous_size: 1024})
      ]
    })
    |> Export.Manifest.save!(job.dest_dir)

    {:ok, lv, _html} = live(conn, ~p"/export-footage")
    select_s3(lv, device)
    lv |> form("#export-form", export: s3_params(device, remote_storage)) |> render_change()

    flags = lv |> element("#upload-flags") |> render()
    assert flags =~ "1 skipped, 1 overwritten"
    assert flags =~ "k/c/12/00_00.mp4"
    assert flags =~ "k/c/13/00_00.mp4 — 1.0 KiB → 2.0 KiB"
    refute flags =~ "k/c/11/00_00.mp4"
  end

  test "only offers the streams the device records", %{conn: conn, tmp_dir: tmp_dir} do
    main_only = camera_device_fixture(tmp_dir)
    {:ok, lv, _html} = live(conn, ~p"/export-footage")

    html = select_s3(lv, main_only)
    assert html =~ "Main stream"
    refute html =~ "Sub stream"
  end

  test "offers the sub stream when it is recorded and resets it when switching device", %{
    conn: conn,
    device: device,
    remote_storage: remote_storage,
    tmp_dir: tmp_dir
  } do
    main_only = camera_device_fixture(tmp_dir)
    {:ok, lv, _html} = live(conn, ~p"/export-footage")
    select_s3(lv, device)

    html =
      lv |> form("#export-form", export: s3_params(device, remote_storage)) |> render_change()

    assert html =~ "Sub stream"

    html =
      lv
      |> form("#export-form", export: s3_params(main_only, remote_storage))
      |> render_change()

    refute html =~ "Sub stream"
    assert lv |> element("#export_stream option[selected]") |> render() =~ "high"
  end

  test "lists recent exports and reopens one", %{
    conn: conn,
    device: device,
    remote_storage: remote_storage
  } do
    {:ok, lv, html} = live(conn, ~p"/export-footage")
    assert html =~ "Recent exports (0)"
    refute html =~ "No exports yet."
    assert lv |> element("#tab-recent a") |> render_click() =~ "No exports yet."
    lv |> element("#tab-export a") |> render_click()

    select_s3(lv, device)
    params = s3_params(device, remote_storage)
    lv |> form("#export-form", export: params) |> render_change()
    lv |> form("#export-form", export: params) |> render_submit()

    {:ok, job} =
      S3.job(
        device,
        remote_storage,
        :low,
        "cam-exid",
        ~U(2024-12-15T11:00:00Z),
        ~U(2024-12-15T12:00:00Z)
      )

    wait_until(fn -> match?({:ok, %{status: :failed}}, Export.progress(job.dest_dir)) end)

    # a fresh page load straight onto the recent tab
    {:ok, lv, html} = live(conn, ~p"/export-footage?tab=recent")
    assert html =~ "Recent exports (1)"
    refute html =~ ~s(id="export-form")
    assert html =~ "S3 · #{remote_storage.name} · kit-1/cam-exid/"
    assert html =~ "2024-12-15 11:00 → 2024-12-15 12:00"
    assert html =~ "no_recordings"

    html = lv |> element(~s(button[phx-click="open_export"])) |> render_click()

    # opening switches back to the export tab with the job loaded
    assert html =~ ~s(id="export-form")
    refute html =~ ~s(id="recent-exports")
    assert html =~ "Export failed: no_recordings"
    assert html =~ "Retry Export"
    assert html =~ ~s(value="cam-exid")
    assert html =~ ~s(value="2024-12-15T11:00")
  end

  test "requires a kit id", %{conn: conn, device: device} do
    remote_storage = remote_storage_fixture(%{s3_config: s3_config(%{})})
    {:ok, lv, _html} = live(conn, ~p"/export-footage")
    select_s3(lv, device)

    html =
      lv
      |> form("#export-form", export: s3_params(device, remote_storage))
      |> render_submit()

    assert html =~ "no kit id available"
  end

  defp select_s3(lv, device) do
    lv
    |> form("#export-form", export: %{"device_id" => device.id, "destination" => "s3"})
    |> render_change()
  end

  defp wait_until(fun, attempts \\ 200)
  defp wait_until(_fun, 0), do: flunk("condition not met in time")

  defp wait_until(fun, attempts) do
    if fun.(), do: :ok, else: Process.sleep(10) && wait_until(fun, attempts - 1)
  end
end
