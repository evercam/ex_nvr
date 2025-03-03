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

  alias ExNVR.Accounts
  alias Req.Response

  @netbird_mangement_url "https://vpn.evercam.io"
  @mountpoint "/data/media"
  @admin_user "admin@evercam.io"
  @default_admin_user "admin@localhost"
  @config_completed_file "/data/.kit_config"

  def start_link(remote_url) do
    GenServer.start_link(__MODULE__, remote_url, name: __MODULE__)
  end

  @impl true
  def init(config) do
    state = %{
      url: config[:url],
      token: config[:token],
      api_version: config[:api_version]
    }

    if File.exists?(@config_completed_file) do
      :ignore
    else
      {:ok, state, {:continue, :configure}}
    end
  end

  @impl true
  def handle_continue(:configure, state), do: configure(state)

  @impl true
  def handle_info(:configure, state), do: configure(state)

  defp configure(state) do
    case Req.get(url(state),
           params: [version: state.api_version],
           headers: [{"x-api-key", state.token}]
         ) do
      {:ok, %Response{status: 200, body: config}} ->
        do_configure(config)
        finalize_config(state, config)
        File.touch!(@config_completed_file)
        {:stop, :normal, state}

      {:ok, %Response{status: 204}} ->
        Logger.info("Already configured, ignore")
        {:stop, :normal, state}

      error ->
        log_error(error)
        Process.send_after(self(), :configure, :timer.seconds(10))
        {:noreply, state}
    end
  end

  defp url(state), do: String.replace(state.url, ":id", kit_id())

  defp kit_id() do
    kit_id = Nerves.Runtime.KV.get("nerves_evercam_id")

    if kit_id == "" do
      {:ok, hostname} = :inet.gethostname()
      List.to_string(hostname)
    else
      kit_id
    end
  end

  defp log_error({:ok, %Response{status: status, body: body}}) do
    Logger.error("[RemoteConfigurer] Received status: #{status} with content: #{inspect(body)}")
  end

  defp log_error({:error, reason}) do
    Logger.error("[RemoteConfigurer] Failed to contact remote server: #{inspect(reason)}")
  end

  defp do_configure(config) do
    connect_to_netbird!(config)
    format_hdd!()
    create_user!(config)
    configure_grafana_agent!(config)
  end

  defp connect_to_netbird!(config) do
    Logger.info("[RemoteConfigurer] Connect to Netbird management server")
    {:ok, _} = ExNVR.Nerves.Netbird.up(@netbird_mangement_url, config["vpn_setup_key"], kit_id())
  end

  def format_hdd!() do
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

        {_output, 0} =
          System.cmd("mkfs.ext4", ["-m", "1", drive.path <> "1"], stderr_to_stdout: true)

        Logger.info("[RemoteConfigurer] Create mountpoint directory: #{@mountpoint}")

        unless File.exists?(@mountpoint) do
          File.mkdir_p!(@mountpoint)
          {_output, 0} = System.cmd("chattr", ["+i", @mountpoint])
        end

        Logger.info("[RemoteConfigurer] Add mountpoint to fstab and mount it")

        part =
          ExNVR.Disk.list_drives!()
          |> Enum.find(&(&1.path == drive.path))
          |> Map.get(:parts)
          |> List.first()

        :ok = ExNVR.Nerves.DiskMounter.add_fstab_entry(part.fs.uuid, @mountpoint, :ext4)
    end
  end

  defp create_user!(config) do
    Logger.info("[RemoteConfigurer] Create admin user")

    if user = Accounts.get_user_by_email(@default_admin_user) do
      Accounts.delete_user(user)
    end

    unless Accounts.get_user_by_email(@admin_user) do
      params = %{
        email: "admin@evercam.io",
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
        kit_id: kit_id()
      )

    ExNVR.Nerves.GrafanaAgent.reconfigure(config)
  end

  defp finalize_config(state, config) do
    body = %{
      mac_address: VintageNet.get(["interface", "eth0", "mac_address"]),
      serial_number: Nerves.Runtime.serial_number(),
      device_name: Nerves.Runtime.KV.get("a.nerves_fw_platform"),
      username: @admin_user,
      password: config["ex_nvr_password"]
    }

    Req.post!(url(state), headers: [{"x-api-key", state.token}], json: body)
  end
end
