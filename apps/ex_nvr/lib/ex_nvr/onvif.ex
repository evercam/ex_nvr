defmodule ExNVR.Onvif do
  @moduledoc """
  Onvif client
  """

  alias ExNVR.Onvif.{Discovery, Http}

  @default_timeout 3_000

  @type url :: binary()
  @type opts :: Keyword.t()

  @doc """
  Probe the network for IP cameras
  """
  @spec discover(opts()) :: {:ok, [map()]} | {:error, term()}
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

  @spec get_device_information(url(), opts()) :: {:error, any} | {:ok, map}
  def get_device_information(url, opts \\ []) do
    url
    |> Http.call("GetDeviceInformation", %{}, opts)
    |> handle_response(Keyword.get(opts, :parse, true))
  end

  @spec get_capabilities(url(), opts()) :: {:error, any} | {:ok, map}
  def get_capabilities(url, opts \\ []) do
    url
    |> Http.call("GetCapabilities", %{}, opts)
    |> handle_response(Keyword.get(opts, :parse, true))
  end

  @spec get_profiles(url(), map, opts()) :: {:error, any} | {:ok, map}
  def get_profiles(url, body, opts \\ []) do
    url
    |> Http.call("GetProfiles", body, Keyword.put(opts, :model, :media))
    |> handle_response(Keyword.get(opts, :parse, true))
  end

  @spec get_stream_uri(url(), map(), opts()) :: {:ok, map()} | {:error, term()}
  def get_stream_uri(url, body, opts \\ []) do
    url
    |> Http.call("GetStreamUri", body, Keyword.put(opts, :model, :media))
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
    {:ok,
     Soap.Response.parse(%{resp | body: String.replace(body, ~r/>\s+</, "><")})
     |> delete_namespaces()}
  end

  defp handle_response(response, _parse), do: response

  defp delete_namespaces(response) when is_map(response) do
    Enum.reduce(response, %{}, fn {key, value}, acc ->
      Map.put(acc, delete_namespace(key), delete_namespaces(value))
    end)
  end

  defp delete_namespaces(response) when is_list(response) do
    Enum.map(response, &delete_namespaces/1)
  end

  defp delete_namespaces({_key, value}), do: delete_namespaces(value)
  defp delete_namespaces(response), do: response

  defp delete_namespace(key) do
    to_string(key)
    |> String.split(":")
    |> List.last()
  end
end
