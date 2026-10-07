defmodule ExNVR.Recordings.ReindexerTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExUnit.CaptureLog

  alias ExMP4.{Box, Reader, Writer}
  alias ExNVR.Model.{Recording, Run}
  alias ExNVR.Pipeline.Output.Storage
  alias ExNVR.Recordings.Reindexer

  @moduletag :tmp_dir

  @device_id UUID.uuid4()
  @fixture "test/fixtures/mp4/big_buck_avc.mp4"

  setup_all do
    reader = Reader.new!(@fixture)
    track = Reader.track(reader, :video)

    samples =
      reader
      |> Reader.stream(tracks: [track.id])
      |> Enum.take(30)
      |> Enum.map(&Reader.read_sample(reader, &1))

    Reader.close(reader)

    %{track: track, samples: samples, device_id: @device_id}
  end

  test "rebuild runs and recordings from mp4 metadata", %{tmp_dir: tmp_dir} = ctx do
    date = ~U(2026-10-01 10:00:00.123456Z)

    r1 = write_file(ctx, tmp_dir, :high, date, run_id: 1)
    r2 = write_file(ctx, tmp_dir, :high, DateTime.add(date, 60), run_id: 1)
    r3 = write_file(ctx, tmp_dir, :high, DateTime.add(date, 3_600), run_id: 5)
    r4 = write_file(ctx, tmp_dir, :low, date, run_id: 2)

    assert {runs, recordings} = Reindexer.scan(tmp_dir, @device_id)

    assert [
             %Recording{stream: :high, run_id: 1} = rec1,
             %Recording{stream: :high, run_id: 1} = rec2,
             %Recording{stream: :high, run_id: 5} = rec3,
             %Recording{stream: :low, run_id: 2} = rec4
           ] = recordings

    for {rec, {start_date, duration}} <- Enum.zip([rec1, rec2, rec3, rec4], [r1, r2, r3, r4]) do
      assert rec.device_id == @device_id
      assert rec.start_date == start_date
      assert rec.end_date == DateTime.add(start_date, duration, :microsecond)
      assert rec.filename == "#{DateTime.to_unix(start_date, :microsecond)}.mp4"
    end

    assert [
             %Run{id: 1, stream: :high, active: false} = run1,
             %Run{id: 5, stream: :high, active: false} = run2,
             %Run{id: 2, stream: :low, active: false} = run3
           ] = runs

    assert Enum.all?(runs, &(&1.device_id == @device_id))
    assert {run1.start_date, run1.end_date} == {rec1.start_date, rec2.end_date}
    assert {run2.start_date, run2.end_date} == {rec3.start_date, rec3.end_date}
    assert {run3.start_date, run3.end_date} == {rec4.start_date, rec4.end_date}
  end

  test "join contiguous recordings of the same run", %{tmp_dir: tmp_dir} = ctx do
    date = ~U(2026-10-01 10:00:00.000000Z)

    {start1, duration} = write_file(ctx, tmp_dir, :high, date, run_id: 1)
    # small gap and small overlap are absorbed
    start2 = DateTime.add(start1, duration + 20_000, :microsecond)
    write_file(ctx, tmp_dir, :high, start2, run_id: 1)
    start3 = DateTime.add(start2, duration - 20_000, :microsecond)
    write_file(ctx, tmp_dir, :high, start3, run_id: 1)
    # big gap is kept
    start4 = DateTime.add(start3, duration + 500_000, :microsecond)
    write_file(ctx, tmp_dir, :high, start4, run_id: 1)
    # contiguous but different run
    write_file(ctx, tmp_dir, :high, DateTime.add(start4, duration, :microsecond), run_id: 2)

    assert {[run1, _run2], [rec1, rec2, rec3, rec4, _rec5]} = Reindexer.scan(tmp_dir, @device_id)

    assert rec1.end_date == start2
    assert rec2.end_date == start3
    assert rec3.end_date == DateTime.add(start3, duration, :microsecond)
    assert rec4.end_date == DateTime.add(start4, duration, :microsecond)
    assert {run1.start_date, run1.end_date} == {start1, rec4.end_date}
  end

  test "skip files without metadata or unreadable", %{tmp_dir: tmp_dir} = ctx do
    date = ~U(2026-10-01 10:00:00.000000Z)

    {start_date, _duration} = write_file(ctx, tmp_dir, :high, date, run_id: 1)
    write_file(ctx, tmp_dir, :high, DateTime.add(date, 60), metadata: false)
    write_file(ctx, tmp_dir, :high, DateTime.add(date, 120), metadata: "not json")

    corrupted = recording_path(tmp_dir, @device_id, :high, DateTime.add(date, 180))
    File.write!(corrupted, "garbage")

    log =
      capture_log(fn ->
        assert {[%Run{id: 1}], [%Recording{start_date: ^start_date}]} =
                 Reindexer.scan(tmp_dir, @device_id)
      end)

    assert log =~ ":no_metadata"
    assert log =~ ":invalid_metadata"
  end

  test "no recordings directory", %{tmp_dir: tmp_dir} do
    assert {[], []} = Reindexer.scan(tmp_dir, @device_id)
  end

  test "save runs and recordings in the database", %{tmp_dir: tmp_dir} = ctx do
    device = camera_device_fixture(tmp_dir)
    ctx = %{ctx | device_id: device.id}
    date = ~U(2026-10-01 10:00:00.000000Z)

    {start1, duration} = write_file(ctx, tmp_dir, :high, date, run_id: 10)
    start2 = DateTime.add(start1, duration, :microsecond)
    write_file(ctx, tmp_dir, :high, start2, run_id: 10)
    write_file(ctx, tmp_dir, :low, date, run_id: 10)

    assert {runs, recordings} = Reindexer.scan(tmp_dir, device.id, save: true)

    assert runs == Run |> order_by([r], [r.stream, r.start_date]) |> Repo.all()
    assert Enum.all?(runs, &(&1.id != 10))
    assert [%Run{stream: :high} = high_run, %Run{stream: :low} = low_run] = runs

    db_recordings = Recording |> order_by([r], [r.stream, r.start_date]) |> Repo.all()
    assert recordings == db_recordings

    assert [
             %Recording{stream: :high, start_date: ^start1, end_date: ^start2},
             %Recording{stream: :high, start_date: ^start2},
             %Recording{stream: :low, start_date: ^date}
           ] = recordings

    assert Enum.map(recordings, & &1.run_id) == [high_run.id, high_run.id, low_run.id]
  end

  defp write_file(ctx, tmp_dir, stream, start_date, opts) do
    %{track: track, samples: samples, device_id: device_id} = ctx
    path = recording_path(tmp_dir, device_id, stream, start_date)

    writer =
      Writer.new!(path)
      |> Writer.write_header()
      |> Writer.add_track(%{track | id: nil})

    writer = Enum.reduce(samples, writer, &Writer.write_sample(&2, %{&1 | track_id: 1}))

    uuid =
      case Keyword.get(opts, :metadata, true) do
        false ->
          []

        true ->
          metadata = %{
            run_id: opts[:run_id],
            start_date: DateTime.to_unix(start_date, :millisecond)
          }

          [Box.UUID.new(Storage.metadata_uuid(), Jason.encode!(metadata))]

        data ->
          [Box.UUID.new(Storage.metadata_uuid(), data)]
      end

    :ok = Writer.write_trailer(writer, uuid: uuid)

    reader = Reader.new!(path)
    duration = Reader.duration(reader, :microsecond)
    Reader.close(reader)

    {start_date, duration}
  end

  defp recording_path(tmp_dir, device_id, stream, start_date) do
    dir = if stream == :high, do: "hi_quality", else: "lo_quality"

    path =
      Path.join(
        [tmp_dir, "ex_nvr", device_id, dir | ExNVR.Utils.date_components(start_date)] ++
          ["#{DateTime.to_unix(start_date, :microsecond)}.mp4"]
      )

    File.mkdir_p!(Path.dirname(path))
    path
  end
end
