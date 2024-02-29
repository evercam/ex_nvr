defmodule ExNVR.HLS.Processor do
  @moduledoc """
  A module transforming the manifest files (*.m3u8) in some ways.

  Currently it has two jobs:
    * Delete manifest definitions from index manifest file (index.m3u8)
    * Add query parameters to manifest definition and segment files
  """

  @doc """
  Delete a stream from master manifest.

  The provided `stream_name` should be a prefix of the stream to delete
  """
  @spec delete_stream(binary(), binary()) :: binary()
  def delete_stream(manifest_content, stream_name) do
    manifest_file_lines = String.split(manifest_content, "\n")

    case Enum.find_index(manifest_file_lines, &String.starts_with?(&1, stream_name)) do
      nil ->
        manifest_content

      idx ->
        manifest_file_lines
        |> Enum.with_index()
        |> Enum.reject(fn {_, index} -> index in [idx - 1, idx] end)
        |> Enum.map_join("\n", fn {line, _} -> line end)
    end
  end

  @spec add_query_params(binary(), Enumerable.t()) :: binary()
  def add_query_params(manifest_content, query_params) do
    encoded_params = URI.encode_query(query_params)

    manifest_content
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      cond do
        String.match?(line, ~r/.+\.mp4"$/) ->
          String.replace(line, ~r/(.+\.mp4)"$/, "\\1?#{encoded_params}\"")

        String.ends_with?(line, [".m3u8", ".m4s"]) ->
          "#{line}?#{encoded_params}"

        true ->
          line
      end
    end)
  end
end
