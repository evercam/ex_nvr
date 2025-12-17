defmodule ExNVR.Nerves.RemoteConfigurer.Router do
  @moduledoc false
  # Router configuration

  require Logger

  alias ExNVR.Nerves.{RUT, SystemSettings}

  defp configure_router(%{"default_password" => passwd}) do
    Logger.info("[RemoteConfigurer] Configure router")
    curr_passwd = SystemSettings.get_settings().router.password

    if is_nil(curr_passwd) do
      SystemSettings.update!(%{
        "router" => %{"password" => passwd, "username" => @router_username}
      })
    end

    curr_passwd = curr_passwd || passwd

    with {:ok, info} <- RUT.system_information(),
         info <- %{serial_number: info.serial, model: info.model},
         {:ok, new_config} <- RemoteConnection.push_and_wait("router-info", info),
         :ok <- update_router_password(curr_passwd, new_config["password"]) do
      Logger.info("[RemoteConfigurer] Router updated password successfully")
      :ok
    end

    # other config
    case set_auto_reboot_schedule() do
      {:ok, _} ->
        Logger.info("[RemoteConfigurer] Router auto reboot schedule set successfully")
        :ok

      {:error, reason} ->
        Logger.error("[RemoteConfigurer] Failed to set router auto reboot schedule: #{inspect(reason)}")
        :error
    end
  end

  defp configure_router(_) do
    Logger.warning("[RemoteConfigurer] No default password provided for router configuration")
  end

  defp update_router_password(curr_passwd, new_passwd) do
    with {:error, _} <- RUT.change_password_firstlogin(new_passwd),
         {:error, _} <- update_user_password(@router_username, curr_passwd, new_passwd) do
      {:error, :failed_to_update_router_password}
    else
      _ok ->
        SystemSettings.update!(%{
          "router" => %{"username" => @router_username, "password" => new_passwd}
        })

        :ok
    end
  end

  defp update_user_password(username, current_pass, new_password) do
    with {:ok, users} <- RUT.users_config() do
      user = Enum.find(users, &(&1["username"] == username))

      config = %{
        current_password: current_pass,
        password: new_password,
        password_confirm: new_password
      }

      RUT.update_user_config(user["id"], config)
    end
  end

  def set_auto_reboot_schedule() do
    days = ["tue", "wed", "thu", "fri", "sat", "sun", "mon"]
    params = %{enable: "1", action: "1", period: "week", days: days, time: ["00:30"]}

    with {:ok, schedules} <- RUT.get_reboot_schedule(),
         {:ok, _ids} <- RUT.delete_reboot_schedule(Enum.map(schedules, & &1["id"])),
         {:ok, result} <- RUT.create_reboot_schedule(params) do
      result
    end
  end
end
