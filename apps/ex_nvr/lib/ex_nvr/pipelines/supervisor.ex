defmodule ExNVR.Pipelines.Supervisor do
  @moduledoc """
  A dynamic supervisor for all the pipelines
  """

  use DynamicSupervisor

  import ExNVR.Utils

  alias ExNVR.Model.Device
  alias ExNVR.Pipeline

  def start_link(_opts) do
    DynamicSupervisor.start_link(strategy: :one_for_one, name: __MODULE__)
  end

  def start_pipeline(%Device{} = device) do
    options = [
      device_id: device.id,
      stream_uri: build_stream_uri(device)
    ]

    File.mkdir_p!(recording_dir(device.id))
    File.mkdir_p!(hls_dir(device.id))

    DynamicSupervisor.start_child(__MODULE__, {Pipeline, options})
  end

  defp build_stream_uri(%Device{ip_camera_config: config}) do
    userinfo =
      if to_string(config.username) != "" and to_string(config.password) != "" do
        "#{config.username}:#{config.password}"
      end

    config
    |> Map.fetch!(:stream_uri)
    |> URI.parse()
    |> then(&%URI{&1 | userinfo: userinfo})
    |> URI.to_string()
  end
end
