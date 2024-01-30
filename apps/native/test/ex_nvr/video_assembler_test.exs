defmodule ExNVR.VideoAssemblerTest do
  use ExUnit.Case

  @moduletag :tmp_dir

  alias ExNVR.VideoAssembler

  setup %{tmp_dir: tmp_dir} do
    recordings = [
      {~U(2023-06-23 10:00:00Z), ~U(2023-06-23 10:00:05Z), Path.join(tmp_dir, "1.mp4")},
      {~U(2023-06-23 10:00:05Z), ~U(2023-06-23 10:00:10Z), Path.join(tmp_dir, "2.mp4")},
      {~U(2023-06-23 10:00:13Z), ~U(2023-06-23 10:00:18Z), Path.join(tmp_dir, "3.mp4")}
    ]

    Enum.each(recordings, &File.cp!("test/fixtures/mp4/big_buck_avc.mp4", elem(&1, 2)))

    %{recordings: recordings}
  end

  test "using native assembler", %{recordings: recordings, tmp_dir: tmp_dir} do
    recs =
      Enum.map(recordings, fn {start_date, end_date, path} ->
        VideoAssembler.Download.new(start_date, end_date, path)
      end)

    start_date = DateTime.to_unix(~U(2023-06-23 10:00:03Z), :millisecond)
    end_date = DateTime.to_unix(~U(2023-06-23 10:00:15Z), :millisecond)
    destination = Path.join(tmp_dir, "output.mp4")

    assert {:ok, real_start_date} =
             VideoAssembler.Native.assemble_recordings(
               recs,
               start_date,
               end_date,
               0,
               destination
             )

    assert File.exists?(destination)
    assert_in_delta(real_start_date, start_date, 1100)
  end
end
