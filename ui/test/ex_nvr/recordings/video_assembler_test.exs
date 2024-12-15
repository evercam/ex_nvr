defmodule ExNVR.Recordings.VideoAssemblerTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.Recordings.VideoAssembler

  @file_chunk "test/fixtures/mp4/big_buck_avc.mp4"

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    recordings = [
      {@file_chunk, ~U(2024-12-15T11:00:00Z)},
      {@file_chunk, ~U(2024-12-15T11:00:05Z)},
      {@file_chunk, ~U(2024-12-15T11:00:10Z)},
      {@file_chunk, ~U(2024-12-15T11:00:23Z)},
      {@file_chunk, ~U(2024-12-15T11:00:28Z)}
    ]

    %{recordings: recordings, dest: Path.join(tmp_dir, "test.mp4")}
  end

  test "assemble recordings chunks", %{recordings: recordings, dest: dest} do
    assert footage_date =
             VideoAssembler.assemble(
               recordings,
               ~U(2024-12-15T11:00:03Z),
               ~U(2025-01-01T00:00:00Z),
               3_600,
               dest
             )

    assert DateTime.compare(footage_date, ~U(2024-12-15T11:00:02Z)) == :eq
    assert {:ok, reader} = ExMP4.Reader.new(dest)
    assert ExMP4.Reader.duration(reader, :millisecond) == 23_000
  end

  test "assemble: limit by end date", %{recordings: recordings, dest: dest} do
    assert footage_date =
             VideoAssembler.assemble(
               recordings,
               ~U(2024-12-15T11:00:06Z),
               ~U(2024-12-15T11:00:26Z),
               3_600,
               dest
             )

    assert DateTime.compare(footage_date, ~U(2024-12-15T11:00:05Z)) == :eq
    assert {:ok, reader} = ExMP4.Reader.new(dest)
    # last frame included
    assert ExMP4.Reader.duration(reader, :millisecond) == 13_033
  end

  test "assemble: limit by duration", %{recordings: recordings, dest: dest} do
    assert footage_date =
             VideoAssembler.assemble(
               recordings,
               ~U(2024-12-15T11:00:04Z),
               ~U(2024-12-15T11:00:26Z),
               10,
               dest
             )

    assert DateTime.compare(footage_date, ~U(2024-12-15T11:00:04Z)) == :eq
    assert {:ok, reader} = ExMP4.Reader.new(dest)
    assert ExMP4.Reader.duration(reader, :millisecond) == 10_033
  end

  test "assemble: crop from one file", %{recordings: recordings, dest: dest} do
    assert footage_date =
             VideoAssembler.assemble(
               recordings,
               ~U(2024-12-15T10:00:00Z),
               ~U(2024-12-15T11:00:04Z),
               3,
               dest
             )

    assert DateTime.compare(footage_date, ~U(2024-12-15T11:00:00Z)) == :eq
    assert {:ok, reader} = ExMP4.Reader.new(dest)
    assert ExMP4.Reader.duration(reader, :millisecond) == 3_033
  end

  test "assemble: empty file", %{recordings: recordings, dest: dest} do
    assert footage_date =
             VideoAssembler.assemble(
               recordings,
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
