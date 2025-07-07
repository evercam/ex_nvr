defmodule ExNVR.Devices.Cameras.NTP do
  @moduledoc """
  Module describing an NTP configuration for a camera device.
  """

  alias ExOnvif.Devices.NTP

  @type t :: %__MODULE__{
          dhcp?: boolean(),
          server: String.t()
        }

  defstruct [:dhcp?, :server]

  def from_onvif(%NTP{from_dhcp: true} = ntp) do
    %__MODULE__{dhcp?: true, server: get_server(ntp.ntp_from_dhcp)}
  end

  def from_onvif(%NTP{from_dhcp: false} = ntp) do
    %__MODULE__{dhcp?: true, server: get_server(ntp.ntp_manual)}
  end

  defp get_server(%{type: :dns} = config), do: config.dns_name
  defp get_server(%{type: :ipv4} = config), do: config.ipv4_address
  defp get_server(%{type: :ipv6} = config), do: config.ipv6_address
end
