defmodule ExNVR.Pipeline.Output.Bif.ArchiverTest do
  @moduledoc false

  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @images_folder "../../../../fixtures/bif" |> Path.expand(__DIR__)

  @moduletag :tmp_dir

  test "create bif file", %{tmp_dir: tmp_dir} do
    out_file = Path.join(tmp_dir, "out.bif")

    structure = [
      child(:source, %Testing.Source{output: prepare_buffers()})
      |> child(:archiver, ExNVR.Pipeline.Output.Bif.Archiver)
      |> child(:sink, %Membrane.File.Sink{location: out_file})
    ]

    pid = Testing.Pipeline.start_supervised!(structure: structure)

    assert_pipeline_play(pid)
    assert_end_of_stream(pid, :sink)

    assert File.read!(out_file) == File.read!(Path.join(@images_folder, "ref.bif"))
  end

  defp prepare_buffers() do
    @images_folder
    |> Path.join("*.jpg")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn file ->
      idx = Path.basename(file, ".jpg") |> String.to_integer()

      %Membrane.Buffer{
        payload: File.read!(file),
        pts: Membrane.Time.seconds(idx)
      }
    end)
  end
end
