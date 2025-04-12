defmodule ExNVR.Devices.Onvif do
  @moduledoc false

  alias ExNVR.Model.Device

  @spec discover(Keyword.t()) :: [Onvif.Discovery.Probe.t()]
  def discover(options) do
    Onvif.Discovery.probe(options)
    |> Enum.uniq()
    |> Enum.map(fn probe ->
      # Ignore link local addresses
      probe.address
      |> Enum.reject(&String.starts_with?(&1, ["http://169.254", "https://169.254"]))
      |> then(&Map.put(probe, :address, &1))
    end)
  end

  @spec onvif_device(Device.t()) :: {:ok, Onvif.Device.t()} | {:error, any()}
  def onvif_device(%Device{type: :ip} = device) do
    case Device.http_url(device) do
      nil ->
        {:error, :no_url}

      url ->
        Onvif.Device.new(url, device.credentials.username, device.credentials.password)
    end
  end

  def onvif_device(_device), do: {:error, :not_camera}

  def stream_profiles(%Device{} = device) do
    case onvif_device(device) do
      {:ok, onvif_device} ->
        config = device.stream_config

        [
          {:main_stream, do_get_onvif_stream_profile(onvif_device, config.profile_token)},
          {:sub_stream, do_get_onvif_stream_profile(onvif_device, config.sub_profile_token)}
        ]
        |> Enum.reject(&is_nil(elem(&1, 1)))
        |> Map.new()

      _error ->
        %{}
    end
  end

  defp do_get_onvif_stream_profile(_onvif_device, nil), do: nil
  defp do_get_onvif_stream_profile(_onvif_device, ""), do: nil

  defp do_get_onvif_stream_profile(onvif_device, profile_token) do
    case Onvif.Media.Ver20.GetProfiles.request(onvif_device, [profile_token]) do
      {:ok, [profile]} -> profile
      _other -> nil
    end
  end
end
