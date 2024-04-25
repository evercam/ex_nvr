defmodule ExNVR.Onvif do
  @moduledoc """
  Onvif client
  """

  import ExNVR.Onvif.Utils, only: [delete_namespaces: 1]

  alias ExNVR.Onvif.{Discovery, Http}

  @default_timeout 3_000

  @type url :: binary()
  @type opts :: Keyword.t()

  @type response :: {:error, any} | {:ok, map}

  @allowed_operations [
    get_system_date_and_time: :device,
    get_device_information: :device,
    get_capabilities: :device,
    get_network_interfaces: :device,
    get_profiles: :media,
    get_stream_uri: :media,
    get_snapshot_uri: :media
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

  @spec get_system_date_and_time(url(), opts()) :: response()
  @spec get_system_date_and_time(url()) :: response()
  def get_system_date_and_time(url, opts \\ []) do
    with {:ok, result} <- call(url, :get_system_date_and_time, %{}, opts) do
      {:ok, get_in(result, [:get_system_date_and_time_response, :system_date_and_time])}
    end
  end

  @spec get_device_information(url(), opts()) :: response()
  @spec get_device_information(url()) :: response()
  def get_device_information(url, opts \\ []) do
    with {:ok, result} <- call(url, :get_device_information, %{}, opts) do
      {:ok, result.get_device_information_response}
    end
  end

  @spec get_capabilities(url(), opts()) :: response()
  @spec get_capabilities(url()) :: response()
  def get_capabilities(url, opts \\ []) do
    with {:ok, result} <- call(url, :get_capabilities, %{}, opts) do
      {:ok, get_in(result, [:get_capabilities_response, :capabilities])}
    end
  end

  @spec get_network_interfaces(url(), opts()) :: response()
  @spec get_network_interfaces(url()) :: response()
  def get_network_interfaces(url, opts \\ []) do
    with {:ok, result} <- call(url, :get_network_interfaces, %{}, opts) do
      result =
        get_in(result, [:get_network_interfaces_response, :network_interfaces])
        |> List.wrap()
        |> Enum.map(fn network_interface ->
          network_interface
          |> Map.put(:ip_v4, network_interface[:i_pv4])
          |> Map.put(:ip_v6, network_interface[:i_pv6])
          |> Map.drop([:i_pv4, :i_pv6])
        end)

      {:ok, result}
    end
  end

  @spec get_media_profiles(url(), opts()) :: response()
  @spec get_media_profiles(url()) :: response()
  def get_media_profiles(url, opts \\ []) do
    with {:ok, result} <- call(url, :get_profiles, %{"Type" => "All"}, opts) do
      result =
        Keyword.values(result.get_profiles_response)
        |> Enum.map(fn media_profile ->
          configurations = Map.drop(media_profile.configurations, [:analytics])
          %{media_profile | configurations: configurations}
        end)

      {:ok, result}
    end
  end

  @spec get_media_stream_uri!(url(), binary(), opts()) :: response()
  @spec get_media_stream_uri!(url(), binary()) :: response()
  def get_media_stream_uri!(url, profile_token, opts \\ []) do
    body = %{"ProfileToken" => profile_token, "Protocol" => ""}
    result = call!(url, :get_stream_uri, body, opts)
    get_in(result, [:get_stream_uri_response, :uri])
  end

  @spec get_media_snapshot_uri!(url(), binary(), opts()) :: response()
  @spec get_media_snapshot_uri!(url(), binary()) :: response()
  def get_media_snapshot_uri!(url, profile_token, opts \\ []) do
    body = %{"ProfileToken" => profile_token, "Protocol" => ""}
    result = call!(url, :get_snapshot_uri, body, opts)
    get_in(result, [:get_snapshot_uri_response, :uri])
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

  defp handle_response({:ok, %{status_code: 401}}, _parse), do: {:error, :unauthorized}
  defp handle_response({:ok, response}, _parse), do: {:error, response}
  defp handle_response(response, _parse), do: response
end
