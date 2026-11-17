defmodule ExNVR.Nerves.Netbird.Identity do
  @moduledoc """
  Reports this device's NetBird peer to NervesHub.

  Used by the `NervesHubLink.Extensions.NetworkIdentity` extension, which shows
  it on the device page so the device can be reached over NetBird without
  opening a console first.

  The identifier is the peer's WireGuard public key, since that is what the
  device proves it holds and it does not change. The FQDN and overlay IPs are
  assigned by the management server and can change, so they go in the details,
  which the extension checks again every few minutes.
  """

  @behaviour NervesHubLink.Extensions.NetworkIdentity.Provider

  alias ExNVR.Nerves.Netbird

  @impl true
  def identity do
    case Netbird.status() do
      {:ok, %{"publicKey" => public_key} = status}
      when is_binary(public_key) and public_key != "" ->
        {:ok, %{service: "netbird", identifier: public_key, details: details(status)}}

      # The daemon has no key yet, or isn't logged in to a management server.
      {:ok, _status} ->
        :unavailable

      {:error, :needs_login} ->
        :unavailable

      {:error, output, exit_status} ->
        {:error, {:exit_status, exit_status, String.trim(output)}}
    end
  catch
    # The extension only rescues raises. An exit from the call (the client not
    # started yet, or busy with `netbird up` past the timeout) would take the
    # extension down with it.
    :exit, {:noproc, _call} -> :unavailable
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp details(status) do
    %{
      "fqdn" => status["fqdn"],
      "ip" => address(status["netbirdIp"]),
      "ipv6" => address(status["netbirdIpv6"])
    }
    |> Map.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  # NetBird reports the overlay address with its prefix length ("100.64.0.1/16").
  # The address on its own is what someone pastes into ssh.
  defp address(nil), do: nil
  defp address(cidr), do: cidr |> String.split("/", parts: 2) |> hd()
end
