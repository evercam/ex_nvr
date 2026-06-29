defmodule ExNVR.Recordings.VideoAssemblerTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.{DevicesFixtures, RecordingsFixtures}

  alias ExNVR.Recordings.VideoAssembler

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    device = camera_device_fixture(tmp_dir)

    recording_fixture(device,
      start_date: ~U(2024-12-15T11:00:00Z),
      end_date: ~U(2024-12-15T11:00:05Z)
    )

    recording_fixture(device,
      start_date: ~U(2024-12-15T11:00:05Z),
      end_date: ~U(2024-12-15T11:00:10Z)
    )

    recording_fixture(device,
      start_date: ~U(2024-12-15T11:00:10Z),
      end_date: ~U(2024-12-15T11:00:15Z)
    )

    recording_fixture(device,
      start_date: ~U(2024-12-15T11:00:23Z),
      end_date: ~U(2024-12-15T11:00:28Z)
    )

    recording_fixture(device,
      start_date: ~U(2024-12-15T11:00:28Z),
      end_date: ~U(2024-12-15T11:00:33Z)
    )

    %{device: device, dest: Path.join(tmp_dir, "test.mp4")}
  end

  test "assemble recordings chunks", %{device: device, dest: dest} do
    assert footage_date =
             VideoAssembler.assemble(
               device,
               :high,
               ~U(2024-12-15T11:00:03Z),
               ~U(2025-01-01T00:00:00Z),
               3_600,
               dest
             )

    assert DateTime.compare(footage_date, ~U(2024-12-15T11:00:02Z)) == :eq
    assert {:ok, reader} = ExMP4.Reader.new(dest)
    assert ExMP4.Reader.duration(reader, :millisecond) == 23_000
  end

  test "assemble: limit by end date", %{device: device, dest: dest} do
    assert footage_date =
             VideoAssembler.assemble(
               device,
               :high,
               ~U(2024-12-15T11:00:06Z),
               ~U(2024-12-15T11:00:26Z),
               3_600,
               dest
             )

    assert DateTime.compare(footage_date, ~U(2024-12-15T11:00:05Z)) == :eq
    assert {:ok, reader} = ExMP4.Reader.new(dest)
    assert ExMP4.Reader.duration(reader, :millisecond) == 13_000
  end

  test "assemble: limit by duration", %{device: device, dest: dest} do
    assert footage_date =
             VideoAssembler.assemble(
               device,
               :high,
               ~U(2024-12-15T11:00:04Z),
               ~U(2024-12-15T11:00:26Z),
               10,
               dest
             )

    assert DateTime.compare(footage_date, ~U(2024-12-15T11:00:04Z)) == :eq
    assert {:ok, reader} = ExMP4.Reader.new(dest)
    assert ExMP4.Reader.duration(reader, :millisecond) == 10_000
  end

  test "assemble: crop from one file", %{device: device, dest: dest} do
    assert footage_date =
             VideoAssembler.assemble(
               device,
               :high,
               ~U(2024-12-15T10:00:00Z),
               ~U(2024-12-15T11:00:04Z),
               3,
               dest
             )

    assert DateTime.compare(footage_date, ~U(2024-12-15T11:00:00Z)) == :eq
    assert {:ok, reader} = ExMP4.Reader.new(dest)
    assert ExMP4.Reader.duration(reader, :millisecond) == 3_000
  end

  test "assemble: empty file", %{device: device, dest: dest} do
    assert footage_date =
             VideoAssembler.assemble(
               device,
               :high,
               ~U(2024-12-15T10:00:00Z),
               ~U(2024-12-15T10:01:00Z),
               3,
               dest
             )

    assert DateTime.compare(footage_date, ~U(2024-12-15T11:00:00Z)) == :eq
    assert {:ok, reader} = ExMP4.Reader.new(dest)
    assert ExMP4.Reader.duration(reader, :millisecond) == 0
  end
end
