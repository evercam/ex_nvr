defmodule ExNVR.Nerves.RUT do
  @moduledoc """
  Teltonika router API client.
  """

  alias __MODULE__.{Auth, SystemInformation}

  def system_information() do
    with {:ok, client} <- Auth.get_client() do
      legacy_api? = Req.Request.get_private(client, :legacy)
      url = if legacy_api?, do: "/system/device/info", else: "/system/device/status"

      client
      |> Req.get(url: url)
      |> handle_response()
      |> case do
        {:ok, data} ->
          info = %SystemInformation{
            mac: data["mnfinfo"]["mac"],
            serial: data["mnfinfo"]["serial"],
            name: data["static"]["device_name"],
            model: data["static"]["model"],
            fw_version: data["static"]["fw_version"]
          }

          {:ok, info}

        error ->
          error
      end
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, body["data"]}
  end

  defp handle_response({:ok, %Req.Response{body: body}}) do
    {:error, body["errors"]}
  end

  defp handle_response(other), do: other
end
