defmodule ExNVR.Export.ManifestTest do
  use ExUnit.Case, async: true

  alias ExNVR.Export.Manifest

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    %{
      dest_dir: tmp_dir,
      params: %{
        device_id: "device-1",
        stream: :high,
        start_date: ~U(2024-12-15T11:00:00.000000Z),
        end_date: ~U(2024-12-15T12:00:00.000000Z),
        max_duration: 600,
        max_file_size: 1_000_000
      }
    }
  end

  test "round-trips through save!/2 and load/1", %{dest_dir: dest_dir, params: params} do
    manifest =
      params
      |> Manifest.new()
      |> Map.update!(:files, fn _ ->
        [
          %{
            filename: "export_00000.mp4",
            start_date: ~U(2024-12-15T11:00:00.000000Z),
            end_date: ~U(2024-12-15T11:10:00.000000Z),
            size: 1234
          }
        ]
      end)
      |> Manifest.save!(dest_dir)

    assert {:ok, loaded} = Manifest.load(dest_dir)

    assert loaded.device_id == manifest.device_id
    assert loaded.stream == :high
    assert DateTime.compare(loaded.start_date, manifest.start_date) == :eq
    assert DateTime.compare(loaded.end_date, manifest.end_date) == :eq
    assert DateTime.compare(loaded.cursor, manifest.cursor) == :eq
    assert loaded.max_duration == 600
    assert loaded.max_file_size == 1_000_000
    assert loaded.status == :running
    assert [file] = loaded.files
    assert file.filename == "export_00000.mp4"
    assert DateTime.compare(file.start_date, ~U(2024-12-15T11:00:00.000000Z)) == :eq
    assert file.size == 1234
  end

  test "load/1 returns :not_found when no manifest exists", %{dest_dir: dest_dir} do
    assert Manifest.load(dest_dir) == {:error, :not_found}
  end

  test "load/1 returns :invalid on garbage JSON", %{dest_dir: dest_dir} do
    File.write!(Manifest.manifest_path(dest_dir), "not json")
    assert Manifest.load(dest_dir) == {:error, :invalid}
  end

  test "save!/2 does not leave tmp files behind", %{dest_dir: dest_dir, params: params} do
    params |> Manifest.new() |> Manifest.save!(dest_dir)

    assert File.ls!(dest_dir) == [Path.basename(Manifest.manifest_path(dest_dir))]
  end
end
