defmodule ExNVR do
  @moduledoc false

  alias ExNVR.{Devices, Pipeline}
  alias ExNVR.Model.Device

  @doc """
  Start the main pipeline
  """
  def start() do
    Devices.list()
    |> List.first()
    |> case do
      nil ->
        :ok

      %Device{} = device ->
        Pipeline.start_link(%{device_id: device.id, stream_uri: build_stream_uri(device)})
    end
  end

  defp build_stream_uri(%Device{config: config}) do
    userinfo =
      if to_string(config["username"]) != "" and to_string(config["password"]) != "" do
        "#{config["username"]}:#{config["password"]}"
      end

    config
    |> Map.fetch!("stream_uri")
    |> URI.parse()
    |> then(&%URI{&1 | userinfo: userinfo})
    |> URI.to_string()
  end
end
