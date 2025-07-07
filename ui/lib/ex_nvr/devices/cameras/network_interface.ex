defmodule ExNVR.Devices.Cameras.NetworkInterface do
  @moduledoc """
  Module describing a network interface for a camera device.
  """

  alias Onvif.Devices.NetworkInterface

  defmodule IPAddress do
    @moduledoc """
    Module representing an IP address.
    """

    @type t :: %__MODULE__{
            dhcp: boolean(),
            address: binary(),
            prefix_length: non_neg_integer()
          }

    defstruct [:dhcp, :address, :prefix_length]
  end

  @type t :: %__MODULE__{
          name: binary(),
          hw_address: binary(),
          ipv4: nil | IPAddress.t()
        }

  defstruct [:name, :hw_address, :ipv4]

  def from_onvif(%NetworkInterface{info: info} = interface) do
    %__MODULE__{
      name: info.name,
      hw_address: info.hw_address,
      ipv4: get_ip_config(:ip_v4, interface.ipv4)
    }
  end

  defp get_ip_config(_type, nil), do: nil

  defp get_ip_config(:ip_v4, %NetworkInterface.IPv4{enabled: true, config: config}) do
    do_get_ip_config(config)
  end

  defp get_ip_config(_type, _interface), do: nil

  defp do_get_ip_config(config) do
    dhcp = config.dhcp
    address = if dhcp, do: config.from_dhcp.address, else: config.manual.address
    prefix_length = if dhcp, do: config.from_dhcp.prefix_length, else: config.manual.prefix_length

    %IPAddress{
      dhcp: config.dhcp,
      address: address,
      prefix_length: prefix_length
    }
  end
end
