defmodule ExNVRWeb.API.RtspTesterController do
  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  alias Ecto.Changeset
  alias ExNVR.Devices.RtspTester

  @spec test(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, Changeset.t()}
  def test(conn, params) do
    with {:ok, params} <- validate_test_req_params(params) do
      {status, payload} = test_stream(params.stream_url, params.username, params.password) |> IO.inspect()
      result = %{stream_url: Map.put(payload, :status, status)}

      result =
        if sub_stream = params[:sub_stream_url] do
          {status, payload} = test_stream(sub_stream, params.username, params.password)
          Map.merge(result, %{sub_stream_url: Map.put(payload, :status, status)})
        else
          result
        end

      json(conn, result)
    end
  end

  defp validate_test_req_params(params) do
    types = %{
      stream_url: :string,
      sub_stream_url: :string,
      username: :string,
      password: :string
    }

    {%{}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_required([:stream_url])
    |> Changeset.apply_action(:create)
  end

  defp test_stream(stream_url, username, password) do
    case ExNVR.Devices.RtspTester.test(stream_url, username, password) do
      {:ok, media_data} ->
        {:ok, Map.take(media_data, [:type, :codec, :clock_rate, :payload_type])}

      {:error, %{status: status}} ->
        {:error, wrap_in_map("RTSP server returned status: #{status}")}

      {:error, error} ->
        {:error, wrap_in_map(error)}
    end
  end

  defp wrap_in_map(message), do: %{message: message}
end
