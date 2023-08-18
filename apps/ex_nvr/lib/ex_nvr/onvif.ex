defmodule ExNVR.Onvif do
  @moduledoc """
  Onvif client
  """

  alias ExNVR.Onvif.Discovery

  @onvif_path Path.join([Application.app_dir(:ex_nvr), "priv", "onvif"])
  @device_model_path Path.join(@onvif_path, "devicemgmt.wsdl")
  @default_timeout 3_000

  @doc """
  Probe the network for IP cameras
  """
  @spec discover() :: {:ok, [map()]} | {:error, term()}
  def discover() do
    case Discovery.probe(@default_timeout) do
      {:ok, matches} ->
        Enum.map(matches, fn %{addresses: addrs} = match ->
          Enum.reduce_while(addrs, %{}, fn addr, acc ->
            if check_connectivity?(addr) do
              {:halt, Map.delete(match, :addresses) |> Map.put(:url, addr)}
            else
              {:cont, acc}
            end
          end)
        end)
        |> Enum.filter(&(&1 != %{}))
        |> then(&{:ok, &1})

      error ->
        error
    end
  end

  defp check_connectivity?(address) do
    wsdl = %{init_wsdl_model(@device_model_path) | endpoint: address}

    case Soap.call(wsdl, "GetSystemDateAndTime", %{}) do
      {:ok, %{status_code: 200}} -> true
      _other -> false
    end
  end

  defp init_wsdl_model(path) do
    {:ok, model} = Soap.init_model(path)
    model
  end
end
