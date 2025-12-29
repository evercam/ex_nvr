defmodule ExNVR.Nerves.RemoteConfigurer.Router do
  @moduledoc false

  require Logger

  alias ExNVR.Nerves.{RUT, SystemSettings}
  alias ExNVR.RemoteConnection

  @router_username "admin"

  def configure(%{"default_password" => passwd}) do
    Logger.info("[RemoteConfigurer] start configuring router")
    curr_passwd = SystemSettings.get_settings().router.password

    if is_nil(curr_passwd) do
      Logger.info("[RemoteConfigurer] setting default router credentials")
      SystemSettings.update!(%{router: %{password: passwd, username: @router_username}})
    end

    curr_passwd = curr_passwd || passwd

    with {:ok, info} <- RUT.system_information(),
         info <- %{serial_number: info.serial, model: info.model},
         {:ok, new_config} <- RemoteConnection.push_and_wait("router-info", info) do
      case do_configure(curr_passwd, new_config) do
        {:ok, output} ->
          SystemSettings.update!(%{
            "router" => %{"password" => new_config["password"], "username" => @router_username}
          })

          Logger.info("""
          [RemoteConfigurer] Router configuration output:
          #{output}
          """)

        {:error, reason} ->
          Logger.error("""
          [RemoteConfigurer] Router configuration failed:
          #{inspect(reason)}
          """)
      end
    end
  end

  def configure(_) do
    Logger.warning("[RemoteConfigurer] No default password provided for router configuration")
  end

  defp do_configure(password, new_config) do
    {:ok, ip_addr} = ExNVR.Nerves.Utils.get_default_gateway()

    ssh_params = [
      user: ~c"root",
      password: to_charlist(password),
      user_interaction: false,
      silently_accept_hosts: true
    ]

    Logger.info("[RemoteConfigurer] Connecting to router at #{ip_addr} via SSH")

    with {:ok, ref} <- :ssh.connect(String.to_charlist(ip_addr), 22, ssh_params),
         {:ok, channel} <- :ssh_connection.session_channel(ref, 5000) do
      params = assigns_from_config(new_config)
      cmd_path = Path.join(:code.priv_dir(:ex_nvr_fw), "router/config.eex")

      Logger.info("[RemoteConfigurer] Executing router configuration script")
      do_exec(ref, channel, EEx.eval_file(cmd_path, assigns: params))
    end
  end

  defp do_exec(ref, channel, cmds) do
    case :ssh_connection.exec(ref, channel, cmds, :infinity) do
      :success ->
        check_output(ref, channel)

      :failure ->
        {:error, :exec_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_output(ref, channel, acc \\ <<>>) do
    receive do
      {:ssh_cm, ^ref, {:data, ^channel, _type, data}} ->
        check_output(ref, channel, <<acc::binary, data::binary>>)

      {:ssh_cm, ^ref, {:closed, ^channel}} ->
        {:ok, acc}

      {:ssh_cm, ^ref, {:exit_status, ^channel, status}} ->
        status = if status != 0, do: :error, else: :ok
        {status, acc}
    end
  end

  defp assigns_from_config(config) do
    params = [
      wifi_password: config["password"],
      password: config["password"],
      timezone: config["timezone"] || "UTC",
      lan_address: config["lan_address"] || "192.168.8.1",
      configure_wg?: config["private_key"] != nil,
      wg_private_key: config["private_key"],
      wg_public_key: config["public_key"],
      wg_address: config["peer_ip"],
      wg_server_ip: config["server_ip"],
      wg_server_public_key: config["server_public_key"]
    ]
  end
end
