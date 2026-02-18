defmodule ExNVR.Nerves.RUT do
  @moduledoc """
  Teltonika router API client.
  """

  alias __MODULE__.{Auth, Scheduler, SystemInformation}

  def system_information do
    do_request(nil, "/system/device/status", fn data ->
      %SystemInformation{
        mac: data["mnfinfo"]["mac"],
        serial: data["mnfinfo"]["serial"],
        name: data["static"]["device_name"],
        model: data["static"]["model"],
        fw_version: data["static"]["fw_version"]
      }
    end)
  end

  def io_status, do: do_request(nil, "/io/status")

  def scheduler do
    with {:ok, client} <- Auth.get_client(),
         {:ok, data} <- do_request(client, "/io/scheduler/global"),
         {:ok, instances} <- do_request(client, "/io/scheduler/config") do
      {:ok, Scheduler.from_response(data, instances)}
    end
  end

  def set_scheduler(schedule) do
    with {:ok, client} <- Auth.get_client(),
         {:ok, scheduler} <- scheduler(),
         {:ok, io_pins} <- io_status() do
      delete_instances =
        if not Enum.empty?(scheduler.instances) do
          %{
            endpoint: "/api/io/scheduler/config",
            method: "DELETE",
            data: Enum.map(scheduler.instances, & &1.id)
          }
        end

      io_pins =
        io_pins
        |> Enum.filter(&(&1["id"] in ["dout1", "relay0"]))
        |> Enum.map(fn
          %{"id" => "dout1", "value" => value} -> {"dout1", String.to_integer(value)}
          %{"id" => "relay0", "state" => "closed"} -> {"relay0", 1}
          _relay -> {"relay0", 0}
        end)

      instances_body =
        io_pins
        |> Enum.flat_map(fn {pin, state} ->
          Scheduler.new_instances(schedule || %{}, pin, state)
        end)
        |> Enum.map(fn instance ->
          %{
            endpoint: "/api/io/scheduler/config",
            method: "POST",
            data: Scheduler.serialize_instance(instance)
          }
        end)

      enable_schedule? = not is_nil(schedule) and instances_body != []

      bulk_body =
        %{
          data:
            [
              %{
                endpoint: "/api/io/scheduler/global",
                method: "PUT",
                data: %{enabled: if(enable_schedule?, do: "1", else: "0")}
              }
            ] ++ List.wrap(delete_instances) ++ instances_body
        }

      client
      |> Req.post(url: "/bulk", json: bulk_body)
      |> handle_response(true)
    end
  end

  def change_password_firstlogin(new_password) do
    with {:ok, client} <- Auth.get_client() do
      body = %{
        password: new_password,
        password_confirm: new_password
      }

      client
      |> Req.post(url: "/system/actions/change_password_firstlogin", json: %{data: body})
      |> handle_response()
    end
  end

  def users_config, do: do_request(nil, "/users/config")

  def update_user_config(id, config) do
    with {:ok, client} <- Auth.get_client() do
      client
      |> Req.put(url: "/users/config/#{id}", json: %{data: config})
      |> handle_response()
    end
  end

  # download the latest stable firmware
  def fota_download do
    with {:ok, client} <- Auth.get_client() do
      client
      |> Req.post(url: "/firmware/actions/fota_download")
      |> handle_response()
    end
  end

  def upgrade_firmware(keep_settings \\ true) do
    with {:ok, client} <- Auth.get_client() do
      body = %{keep_settings: if(keep_settings, do: "1", else: "0")}

      client
      |> Req.post(url: "/firmware/actions/upgrade", json: %{data: body})
      |> handle_response()
    end
  end

  def factory_reset(user_defaults \\ false) do
    with {:ok, client} <- Auth.get_client() do
      body = %{user_defaults: if(user_defaults, do: "1", else: "0")}

      client
      |> Req.post(url: "/firmware/actions/factory_reset", json: %{data: body})
      |> handle_response()
    end
  end

  def get_firewall_zones do
    do_request(nil, "/firewall/zones/config")
  end

  def create_firewall_zone(zone_config) do
    with {:ok, client} <- Auth.get_client() do
      client
      |> Req.post(url: "/firewall/zones/config", json: %{data: zone_config})
      |> handle_response()
    end
  end

  # Reboot Schedule
  def get_reboot_schedule do
    do_request(nil, "/auto_reboot/scheduler/config")
  end

  def create_reboot_schedule(params) do
    with {:ok, client} <- Auth.get_client() do
      client
      |> Req.post(url: "/auto_reboot/scheduler/config", json: %{data: params})
      |> handle_response()
    end
  end

  def delete_reboot_schedule([]), do: {:ok, []}

  def delete_reboot_schedule(ids) do
    with {:ok, client} <- Auth.get_client() do
      client
      |> Req.delete(url: "/auto_reboot/scheduler/config", json: %{data: ids})
      |> handle_response()
    end
  end

  defp do_request(client, url, response_handler \\ &Function.identity/1)

  defp do_request(nil, url, response_handler) do
    with {:ok, client} <- Auth.get_client() do
      do_request(client, url, response_handler)
    end
  end

  defp do_request(client, url, response_handler) do
    client
    |> Req.get(url: url)
    |> handle_response()
    |> case do
      {:ok, data} -> {:ok, response_handler.(data)}
      error -> error
    end
  end

  defp handle_response(response, bulk \\ false)

  defp handle_response({:ok, %Req.Response{body: %{"success" => true} = body}}, bulk) do
    cond do
      bulk and Enum.any?(body["data"], &(&1["success"] == false)) ->
        {:error, body["data"]}

      is_nil(body["data"]) ->
        :ok

      true ->
        {:ok, body["data"]}
    end
  end

  defp handle_response({:ok, %Req.Response{body: %{"success" => false} = body}}, _bulk) do
    {:error, body["errors"]}
  end

  defp handle_response({:ok, %Req.Response{body: body}}, _bulk) do
    {:error, body}
  end

  defp handle_response(other, _bulk), do: other
end
