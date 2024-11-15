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
  @spec delete_stream(String.t(), String.t()) :: binary()
  def delete_stream(manifest_content, stream_name) do
    playlist = ExM3U8.deserialize_multivariant_playlist!(manifest_content)
    streams = Enum.reject(playlist.items, &String.starts_with?(&1.uri, stream_name))
    ExM3U8.serialize(%{playlist | items: streams})
  end

  @spec add_query_params(String.t(), :media_playlist | :playlist, Enumerable.t()) :: binary()
  def add_query_params(manifest_content, :media_playlist, query_params) do
    encoded_params = URI.encode_query(query_params)
    playlist = ExM3U8.deserialize_media_playlist!(manifest_content, [])

    timeline =
      Enum.map(playlist.timeline, fn
        %{uri: uri} = entry -> %{entry | uri: uri <> "?#{encoded_params}"}
        entry -> entry
      end)

    ExM3U8.serialize(%{playlist | timeline: timeline})
  end

  def add_query_params(manifest_content, :playlist, query_params) do
    playlist = ExM3U8.deserialize_multivariant_playlist!(manifest_content, [])
    items = Enum.map(playlist.items, &%{&1 | uri: &1.uri <> "?#{URI.encode_query(query_params)}"})
    ExM3U8.serialize(%{playlist | items: items})
  end
end
