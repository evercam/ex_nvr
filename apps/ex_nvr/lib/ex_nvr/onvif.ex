defmodule ExNVR.Onvif do
  @moduledoc """
  Onvif client
  """

  alias ExNVR.Onvif.{Discovery, Http}

  @default_timeout 3_000

  @type url :: binary()
  @type opts :: Keyword.t()

  @allowed_operations [
    get_system_date_and_time: :device,
    get_device_information: :device,
    get_capabilities: :device,
    get_network_interfaces: :device,
    get_profiles: :media,
    get_stream_uri: :media
  ]

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

  @spec call(url(), atom(), map(), opts()) :: {:error, any} | {:ok, map}
  def call(url, operation, body \\ %{}, opts \\ []) do
    model = Keyword.fetch!(@allowed_operations, operation)
    opts = Keyword.put(opts, :model, model)

    url
    |> Http.call(Macro.camelize(to_string(operation)), body, opts)
    |> handle_response(Keyword.get(opts, :parse, true))
  end

  @spec call!(url(), atom(), map(), opts()) :: map
  def call!(url, operation, body \\ %{}, opts \\ []) do
    case call(url, operation, body, opts) do
      {:ok, response} ->
        response

      {:error, error} ->
        raise """
        could not execute operation: #{operation}
        #{inspect(error)}
        """
    end
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

  defp handle_response({:ok, response}, _parse), do: {:error, response}
  defp handle_response(response, _parse), do: response

  defp delete_namespaces(response) when is_map(response) do
    Enum.reduce(response, %{}, fn {key, value}, acc ->
      Map.put(acc, delete_namespace(key), delete_namespaces(value))
    end)
  end

  defp delete_namespaces(response) when is_list(response) do
    Enum.map(response, &delete_namespaces/1)
  end

  defp delete_namespaces({key, value}) do
    {delete_namespace(key), delete_namespaces(value)}
  end

  defp delete_namespaces(response), do: response

  defp delete_namespace(key) do
    to_string(key)
    |> String.split(":")
    |> List.last()
    |> String.to_atom()
  end
end
