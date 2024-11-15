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

  alias Req.Response

  @netbird_mangement_url "https://vpn.evercam.io"
  @mountpoint "/data/media"
  @admin_user "admin@evercam.io"

  def start_link(remote_url) do
    GenServer.start_link(__MODULE__, remote_url, name: __MODULE__)
  end

  @impl true
  def init(config) do
    state = %{
      url: config[:url],
      token: config[:token]
    }

    {[], state, continue: :configure}
  end

  @impl true
  def handle_continue(:configure, state), do: configure(state)

  @impl true
  def handle_info(:configure, state), do: configure(state)

  defp configure(state) do
    case Req.get(url(state), headers: [{"x-api-key", state.token}]) do
      {:ok, %Response{status: 200, body: config}} ->
        do_configure(config)
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
    Logger.error("Received status: #{status} with content: #{inspect(body)}")
  end

  defp log_error({:error, reason}) do
    Logger.error("Failed to contact remote server: #{inspect(reason)}")
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

  defp format_hdd!() do
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
        {_output, 0} = System.cmd("mkfs.ext4", [drive.path <> "1"], stderr_to_stdout: true)

        Logger.info("[RemoteConfigurer] Create mountpoint directory: #{@mountpoint}")
        File.mkdir_p!(@mountpoint)

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

    unless ExNVR.Accounts.get_user(@admin_user) do
      params = %{
        email: "admin@evercam.io",
        password: config["ex_nvr_password"],
        role: :admin,
        first_name: "Admin",
        last_name: "Admin"
      }

      {:ok, _user} = ExNVR.Accounts.register_user(params)
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
end
