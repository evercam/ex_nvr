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

  alias __MODULE__.Router
  alias ExNVR.{Accounts, RemoteConnection}
  alias ExNVR.Nerves.{DiskMounter, GrafanaAgent, Netbird, RUT, SystemSettings, Utils}
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
        mac_address: VintageNet.get(["interface", "eth0", "mac_address"]),
        serial_number: Runtime.serial_number(),
        device_name: Runtime.KV.get("a.nerves_fw_platform"),
        version: @config_version,
        gateway_mac_address: mac_addr
      }

      case RemoteConnection.push_and_wait("register-kit", payload, @call_timeout) do
        :ok ->
          Logger.info("Device already configured, finalizing...")
          finalize_config(state.kit_serial)
          {:stop, :normal, state}

        {:ok, params} ->
          Logger.info("Received configuration from remote server, applying...")
          do_configure(params)
          finalize_config(params["serial"])
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
    connect_to_netbird!(config)
    format_hdd!()
    create_user!(config)
    configure_grafana_agent!(config)
    Router.configure(config["gateway_config"])
  end

  defp connect_to_netbird!(config) do
    Logger.info("[RemoteConfigurer] Connect to Netbird management server")
    {:ok, _} = Netbird.up(@netbird_mangement_url, config["vpn_setup_key"], config["serial"])
  end

  def format_hdd! do
    ExNVR.Disk.list_drives!()
    |> Enum.reject(&ExNVR.Disk.has_filesystem?/1)
    |> case do
      [] ->
        Logger.warning("No unformatted hard drive found")

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
    end
  end

  defp create_user!(config) do
    Logger.info("[RemoteConfigurer] Create admin user")

    case Accounts.get_user_by_email(@default_admin_user) do
      nil -> :ok
      user -> Accounts.delete_user(user)
    end

    admin_user = config["ex_nvr_username"]

    unless Accounts.get_user_by_email(admin_user) do
      params = %{
        email: admin_user,
        password: config["ex_nvr_password"],
        role: :admin,
        first_name: "Admin",
        last_name: "Admin"
      }

      {:ok, _user} = Accounts.register_user(params)
    end
  end

  defp configure_grafana_agent!(config) do
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
  end

  defp finalize_config(kit_serial) do
    SystemSettings.update!(%{"kit_serial" => kit_serial})
    :ok = RemoteConnection.push_and_wait("config-completed", %{}, @call_timeout)
    SystemSettings.update!(%{"configured" => true})
  end

  defp get_disk_first_part(path) do
    ExNVR.Disk.list_drives!()
    |> Enum.find(&(&1.path == path))
    |> Map.get(:parts)
    |> List.first()
  end
end
