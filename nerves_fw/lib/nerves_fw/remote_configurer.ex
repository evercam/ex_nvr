defmodule ExNVR.Nerves.RemoteConfigurer do
  @moduledoc """
  Complete configuration of the device using remote configuration.

  This module will contact a cloud endpoint to fetch configuration to apply to the device,
  it'll be responsible for:

    * Connecting to netbird management server.
    * Format and mount a hard drive.
    * Create a new user with the provided credentials.
    * Configure grafana agent.
  """

  use GenServer, restart: :transient

  require Logger

  alias __MODULE__.{Router, Step}
  alias ExNVR.{Accounts, RemoteConnection}
  alias ExNVR.Nerves.{Application, DiskMounter, GrafanaAgent, Netbird, SystemSettings, Utils}
  alias ExNVR.Nerves.RecomputerR22.{ATModem, SimConfigurer}
  alias Nerves.Runtime

  @netbird_mangement_url "https://vpn.evercam.io"
  @mountpoint "/data/media"
  @default_admin_user "admin@localhost"
  @config_completed_file "/data/.kit_config"
  @call_timeout to_timeout(second: 20)
  @config_version "1.0"

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(_config) do
    settings =
      if File.exists?(@config_completed_file) do
        # credo:disable-for-next-line
        # TODO: following code will be deleted in the next version
        kit_serial = Runtime.KV.get("nerves_evercam_id")
        SystemSettings.update!(%{"configured" => true, "kit_serial" => kit_serial})
      else
        SystemSettings.get_settings()
      end

    if is_nil(settings.kit_serial) or not settings.configured do
      {:ok, %{kit_serial: settings.kit_serial}, {:continue, :configure}}
    else
      :ignore
    end
  end

  @impl true
  def handle_continue(:configure, state), do: configure(state)

  @impl true
  def handle_info(:configure, state), do: configure(state)

  defp configure(state) do
    with pid when is_pid(pid) <- Process.whereis(RemoteConnection),
         {:ok, gateway} <- Utils.get_default_gateway(),
         {:ok, mac_addr} <- Utils.get_mac_address(gateway) do
      payload = %{
        kit_serial: state.kit_serial,
        mac_address: mac_address(),
        serial_number: Runtime.serial_number(),
        device_name: Runtime.KV.get("a.nerves_fw_platform"),
        version: @config_version,
        gateway_mac_address: mac_addr
      }

      case RemoteConnection.push_and_wait("register-kit", payload, @call_timeout) do
        {:ok, kit_serial} when is_binary(kit_serial) ->
          Logger.info("Device already configured, finalizing...")
          finalize_config([], kit_serial)
          {:stop, :normal, state}

        {:ok, params} ->
          Logger.info("Received configuration from remote server, applying...")

          params
          |> do_configure()
          |> finalize_config(params["serial"])

          {:stop, :normal, state}

        {:error, _reason} ->
          Logger.info("Failed to get configuration remotely, retrying...")
          Process.send_after(self(), :configure, :timer.seconds(5))
          {:noreply, state}
      end
    else
      error ->
        Logger.info("Failed to send request #{inspect(error)}, retrying...")
        Process.send_after(self(), :configure, :timer.seconds(10))
        {:noreply, state}
    end
  end

  defp do_configure(config) do
    tasks = [
      Task.async(fn -> connect_to_netbird(config) end),
      Task.async(fn -> format_hdd() end),
      Task.async(fn -> create_user(config) end),
      Task.async(fn -> configure_grafana_agent(config) end),
      Task.async(fn -> configure_gateway(config) end)
    ]

    Task.await_many(tasks, :infinity)
  end

  # The recomputer_r22 has no Teltonika router; it uses a built-in cellular
  # modem instead, so we configure the modem rather than the router.
  defp configure_gateway(config) do
    if Application.target() == :recomputer_r22 do
      configure_modem()
    else
      Router.configure(config["gateway_config"])
    end
  end

  defp configure_modem do
    Logger.info("[RemoteConfigurer] configure 4G modem")

    case ATModem.start() do
      {:ok, _pid} ->
        do_configure_modem()

      {:error, reason} ->
        %Step{name: :configure_modem, status: :error, reason: inspect(reason)}
    end
  end

  defp do_configure_modem do
    with :ok <- ensure_sim_detected(),
         :ok <- ensure_ecm_mode(),
         {:ok, apn} <- SimConfigurer.configure_apn() do
      %Step{name: :configure_modem, status: :ok, reason: "APN set to #{apn}"}
    else
      {:error, reason} ->
        Logger.error("[RemoteConfigurer] modem configuration failed: #{inspect(reason)}")
        %Step{name: :configure_modem, status: :error, reason: inspect(reason)}
    end
  end

  # The SIM must be detected before we can configure the modem. If it isn't,
  # reboot the modem once and re-check; abort if it's still missing.
  defp ensure_sim_detected do
    if sim_detected?(), do: :ok, else: reboot_and_recheck_sim()
  end

  defp reboot_and_recheck_sim do
    Logger.warning("[RemoteConfigurer] SIM not detected, rebooting modem")

    case reboot_modem() do
      :ok -> if sim_detected?(), do: :ok, else: {:error, :sim_not_detected}
      {:error, reason} -> {:error, {:modem_reboot_failed, reason}}
    end
  end

  defp reboot_modem do
    case ATModem.reboot() do
      {:error, :reboot_in_progress} -> wait_for_reboot()
      result -> result
    end
  end

  defp wait_for_reboot do
    case ATModem.ping() do
      {:error, :reboot_in_progress} ->
        Process.sleep(:timer.seconds(2))
        wait_for_reboot()

      {:ok, _} ->
        :ok

      {:error, _reason} ->
        Process.sleep(:timer.seconds(2))
        wait_for_reboot()
    end
  end

  defp sim_detected?, do: match?({:ok, _}, ATModem.sim_status())

  # If the modem connects over QMI/wwan, switch it to usbnet (CDC ECM) so it shows
  # up as usb0. The modem resets itself to apply the mode change.
  defp ensure_ecm_mode do
    case ATModem.usbnet_mode() do
      {:ok, :ecm} ->
        :ok

      {:ok, mode} ->
        Logger.info("[RemoteConfigurer] modem using #{mode}, switching to ECM (usb1)")
        switch_to_ecm()

      {:error, reason} ->
        {:error, {:usbnet_mode_unavailable, reason}}
    end
  end

  defp switch_to_ecm do
    case ATModem.set_usbnet_mode(:ecm) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:set_usbnet_failed, reason}}
    end
  end

  # For the recomputer_r22 we use eth1 as the mac address for authentication; eth0 is unused.
  defp mac_address do
    interface = if Application.target() == :recomputer_r22, do: "eth1", else: "eth0"
    VintageNet.get(["interface", interface, "mac_address"])
  end

  defp connect_to_netbird(config) do
    Logger.info("[RemoteConfigurer] Connect to Netbird management server")

    case Netbird.up(@netbird_mangement_url, config["vpn_setup_key"], config["serial"]) do
      {:ok, _result} -> %Step{name: :netbird, status: :ok}
      {:error, reason} -> %Step{name: :netbird, status: :error, reason: inspect(reason)}
    end
  end

  def format_hdd do
    ExNVR.Disk.list_drives!()
    |> Enum.reject(&ExNVR.Disk.has_filesystem?/1)
    |> case do
      [] ->
        Logger.warning("No unformatted hard drive found")
        %Step{name: :format_hdd, status: :ok, reason: "no unformatted drive found"}

      [drive | _rest] ->
        Logger.info("[RemoteConfigurer] delete all partitions on device: #{drive.path}")
        {_output, 0} = System.cmd("sgdisk", ["--zap-all", drive.path], stderr_to_stdout: true)

        Logger.info("[RemoteConfigurer] create new partition on device: #{drive.path}")
        {_output, 0} = System.cmd("sgdisk", ["--new=1:0:0", drive.path], stderr_to_stdout: true)

        Logger.info("[RemoteConfigurer] create ext4 filesystem on device: #{drive.path}")

        part = get_disk_first_part(drive.path)
        {_output, 0} = System.cmd("mkfs.ext4", ["-m", "0.1", part.path], stderr_to_stdout: true)

        Logger.info("[RemoteConfigurer] Create mountpoint directory: #{@mountpoint}")

        if not File.exists?(@mountpoint) do
          File.mkdir_p!(@mountpoint)
          {_output, 0} = System.cmd("chattr", ["+i", @mountpoint])
        end

        Logger.info("[RemoteConfigurer] Add mountpoint to fstab and mount it")

        part = get_disk_first_part(drive.path)
        :ok = DiskMounter.add_fstab_entry(part.fs.uuid, @mountpoint, :ext4)
        %Step{name: :format_hdd, status: :ok}
    end
  end

  defp create_user(config) do
    Logger.info("[RemoteConfigurer] Create admin user")

    case Accounts.get_user_by_email(@default_admin_user) do
      nil -> :ok
      user -> Accounts.delete_user(user)
    end

    admin_user = config["ex_nvr_username"]

    case Accounts.get_user_by_email(admin_user) do
      nil ->
        params = %{
          email: admin_user,
          password: config["ex_nvr_password"],
          role: :admin,
          first_name: "Admin",
          last_name: "Admin"
        }

        case Accounts.register_user(params) do
          {:ok, _user} ->
            %Step{name: :create_user, status: :ok}

          {:error, changeset} ->
            %Step{
              name: :create_user,
              status: :error,
              reason: "failed to create user: #{inspect(changeset.errors)}"
            }
        end

      _user ->
        %Step{name: :create_user, status: :ok, reason: "user already exists"}
    end
  end

  defp configure_grafana_agent(config) do
    Logger.info("[RemoteConfigurer] Configure grafana agent")

    config =
      Keyword.merge(ExNVR.Nerves.Application.grafana_agent_config(),
        prom_url: config["prom_url"],
        prom_username: config["prom_username"],
        prom_password: config["prom_password"],
        loki_url: config["loki_url"],
        loki_username: config["loki_username"],
        loki_password: config["loki_password"],
        kit_id: config["serial"]
      )

    GrafanaAgent.reconfigure(config)
    %Step{name: :grafana_agent, status: :ok}
  end

  defp finalize_config(steps, kit_serial) do
    SystemSettings.update!(%{"kit_serial" => kit_serial})
    :ok = RemoteConnection.push_and_wait("config-completed", steps, @call_timeout)
    SystemSettings.update!(%{"configured" => true})
  end

  defp get_disk_first_part(path) do
    ExNVR.Disk.list_drives!()
    |> Enum.find(&(&1.path == path))
    |> Map.get(:parts)
    |> List.first()
  end
end
