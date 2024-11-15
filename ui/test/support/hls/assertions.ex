defmodule ExNVR.HLS.Assertions do
  @moduledoc false
  use ExUnit.Case

  def check_hls_playlist(output_dir, manifests_number) do
    output_files = File.ls!(output_dir) |> Enum.sort()

    manifest_files = Enum.filter(output_files, &String.ends_with?(&1, ".m3u8"))
    headers = find_headers(output_files)

    assert Enum.count(manifest_files) == manifests_number
    assert Enum.count(headers) == manifests_number - 1
  end

  defp find_headers(files) do
    Enum.filter(files, &String.match?(&1, ~r/.*header.*$/))
  end
end
