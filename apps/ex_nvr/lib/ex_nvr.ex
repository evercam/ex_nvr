defmodule ExNVR do
  @moduledoc false

  alias ExNVR.{Devices, Pipelines}
  alias ExNVR.Model.Device

  @doc """
  Start the main pipeline
  """
  def start() do
    for device <- Devices.list() do
      options = [
        device_id: device.id,
        stream_uri: build_stream_uri(device)
      ]

      Pipelines.Supervisor.start_pipeline(options)
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
