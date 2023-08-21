defmodule ExNVR.Onvif do
  @moduledoc """
  Onvif client
  """

  import Mockery.Macro

  alias ExNVR.Onvif.Discovery

  @onvif_path Path.join([Application.app_dir(:ex_nvr), "priv", "onvif"])
  @device_model_path Path.join(@onvif_path, "devicemgmt.wsdl")
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

  defp check_connectivity?(address) do
    wsdl = %{init_wsdl_model(@device_model_path) | endpoint: address}

    case mockable(Soap).call(wsdl, "GetSystemDateAndTime", %{}) do
      {:ok, %{status_code: 200}} -> true
      _other -> false
    end
  end

  defp init_wsdl_model(path) do
    {:ok, model} = Soap.init_model(path)
    model
  end
end
