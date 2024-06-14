defmodule ExNVR.BIF.WriterTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.BIF.Writer

  @images_folder "../../fixtures/bif" |> Path.expand(__DIR__)

  @moduletag :tmp_dir

  test "create bif file", %{tmp_dir: tmp_dir} do
    out_file = Path.join(tmp_dir, "out.bif")
    writer = Writer.new(out_file)

    writer =
      @images_folder
      |> Path.join("*.jpg")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reduce(writer, fn file, writer ->
        idx = Path.basename(file, ".jpg") |> String.to_integer()

        Writer.write!(writer, File.read!(file), idx)
      end)

    Writer.finalize!(writer)

    assert File.read!(out_file) == File.read!(Path.join(@images_folder, "ref.bif"))
  end
end
