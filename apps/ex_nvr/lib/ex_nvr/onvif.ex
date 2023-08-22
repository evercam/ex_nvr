defmodule ExNVR.Onvif do
  @moduledoc """
  Onvif client
  """

  alias ExNVR.Onvif.{Discovery, Http}

  @default_timeout 3_000

  @doc """
  Probe the network for IP cameras
  """
  @spec discover(Keyword.t()) :: {:ok, [map()]} | {:error, term()}
  def discover(opts \\ []) do
    timeout = opts[:timeout] || @default_timeout

    case Discovery.probe(timeout) do
      {:ok, matches} ->
        matches
        |> Enum.map(fn %{addresses: addrs} = match ->
          match
          |> Map.delete(:addresses)
          |> Map.put(:url, Enum.find(addrs, &check_connectivity?/1))
        end)
        |> Enum.reject(&is_nil(&1.url))
        |> then(&{:ok, &1})

      error ->
        error
    end
  end

  def get_device_information(url, opts \\ []) do
    url
    |> Http.call("GetDeviceInformation", %{}, opts)
    |> handle_response(Keyword.get(opts, :parse, true))
  end

  def get_capabilities(url, opts \\ []) do
    url
    |> Http.call("GetCapabilities", %{}, opts)
    |> handle_response(Keyword.get(opts, :parse, true))
  end

  defp check_connectivity?(address) do
    case Http.call(address, "GetSystemDateAndTime", %{}) do
      {:ok, %{status_code: 200}} -> true
      _other -> false
    end
  end

  defp handle_response(response, false), do: response

  defp handle_response({:ok, %{body: body, status_code: 200} = resp}, _parse) do
    {:ok, Soap.Response.parse(%{resp | body: String.replace(body, ["\r\n", "\r", "\n"], "")})}
  end

  defp handle_response(response, _parse), do: response
end
