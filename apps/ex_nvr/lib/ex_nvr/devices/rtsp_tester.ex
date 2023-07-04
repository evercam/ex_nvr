defmodule ExNVR.Devices.RtspTester do
  @moduledoc """
  Test an RTSP url connectivity and get video media information
  """

  alias ExNVR.MediaTrack
  alias Membrane.RTSP

  @spec test(binary(), binary(), binary()) :: any()
  def test(stream_url, username, password) do
    url = %URI{URI.parse(stream_url) | userinfo: "#{username}:#{password}"}

    case RTSP.start(url) do
      {:ok, session} ->
        result = do_test(session)
        RTSP.close(session)
        result

      {:error, error} ->
        {:error, error}
    end
  end

  defp do_test(session) do
    with {:ok, sdp} <- describe_session(session),
         {:ok, video_media} <- get_video_media(sdp) do
      {:ok, MediaTrack.from_sdp(video_media)}
    end
  end

  defp describe_session(session, retried \\ false) do
    case RTSP.describe(session, [{"content-type", "application/sdp"}]) do
      {:ok, %{status: 401}} ->
        if retried,
          do: {:error, :unauthorized},
          else: describe_session(session, true)

      {:ok, %{status: 200} = response} ->
        {:ok, response.body}

      {:ok, response} ->
        {:error, response}

      {:error, error} ->
        {:error, error}
    end
  catch
    :exit, error ->
      {:error, error}
  end

  defp get_video_media(%ExSDP{media: medias}) do
    case Enum.find(medias, & &1.type == :video) do
      nil -> {:error, :no_video_media}
      video_media -> {:ok, video_media}
    end
  end
end
