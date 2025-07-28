defmodule ExNVR.Nerves.RUT do
  @moduledoc """
  Teltonika router API client.
  """

  alias __MODULE__.{Auth, Scheduler, SystemInformation}

  def system_information do
    with {:ok, client} <- Auth.get_client() do
      do_request(client, "/system/device/status", fn data ->
        %SystemInformation{
          mac: data["mnfinfo"]["mac"],
          serial: data["mnfinfo"]["serial"],
          name: data["static"]["device_name"],
          model: data["static"]["model"],
          fw_version: data["static"]["fw_version"]
        }
      end)
    end
  end

  def io_status do
    with {:ok, client} <- Auth.get_client() do
      do_request(client, "/io/status")
    end
  end

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

      bulk_body =
        %{
          data:
            [
              %{
                endpoint: "/api/io/scheduler/global",
                method: "PUT",
                data: %{enabled: if(schedule, do: "1", else: "0")}
              }
            ] ++ List.wrap(delete_instances) ++ instances_body
        }

      client
      |> Req.post(url: "/bulk", json: bulk_body)
      |> handle_response()
    end
  end

  defp do_request(client, url, response_handler \\ &Function.identity/1) do
    client
    |> Req.get(url: url)
    |> handle_response()
    |> case do
      {:ok, data} -> {:ok, response_handler.(data)}
      error -> error
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status >= 200 or status < 300 do
    {:ok, body["data"]}
  end

  defp handle_response({:ok, %Req.Response{body: body}}) do
    {:error, body["errors"]}
  end

  defp handle_response(other), do: other
end
