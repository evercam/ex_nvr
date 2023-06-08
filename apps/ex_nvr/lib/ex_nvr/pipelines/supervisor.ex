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
    {main_stream, sub_stream} = build_stream_uri(device)

    options = [
      device_id: device.id,
      stream_uri: main_stream,
      sub_stream_uri: sub_stream
    ]

    File.mkdir_p!(recording_dir(device.id))
    File.mkdir_p!(hls_dir(device.id))

    DynamicSupervisor.start_child(__MODULE__, {Pipeline, options})
  end

  def restart_pipeline(%Device{} = device) do
    # TODO
    # Think of a way to restart the Pipeline
    # making the Pipeline restart mode to transient
    # doesn't work because of a bug in Membrane
    # https://github.com/membraneframework/membrane_core/issues/566
    :ok
  end

  defp build_stream_uri(%Device{ip_camera_config: config}) do
    userinfo =
      if to_string(config.username) != "" and to_string(config.password) != "" do
        "#{config.username}:#{config.password}"
      end

    {do_build_uri(config.stream_uri, userinfo), do_build_uri(config.sub_stream_uri, userinfo)}
  end

  defp do_build_uri(nil, _userinfo), do: nil

  defp do_build_uri(stream_uri, userinfo) do
    stream_uri
    |> URI.parse()
    |> then(&%URI{&1 | userinfo: userinfo})
    |> URI.to_string()
  end
end
