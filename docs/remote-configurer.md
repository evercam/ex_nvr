# RemoteConfigurer

`ExNVR.Nerves.RemoteConfigurer` performs a one-time setup of the device by contacting a remote server.

## Initialization

At startup a state struct is built from the provided options. If `/data/.kit_config` already exists the process stops; otherwise it continues with configuration.

```elixir
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
```

## Configuration Steps

`configure/1` downloads settings from the server and executes the tasks:

```elixir
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
```

`do_configure/1` orchestrates the following actions:

```elixir
defp do_configure(config) do
  connect_to_netbird!(config)
  format_hdd!()
  create_user!(config)
  configure_grafana_agent!(config)
end
```

Formatting the disk and mounting it involves:

```elixir
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
    {_output, 0} = System.cmd("mkfs.ext4", ["-m", "1", part.path], stderr_to_stdout: true)

    Logger.info("[RemoteConfigurer] Create mountpoint directory: #{@mountpoint}")

    if not File.exists?(@mountpoint) do
      File.mkdir_p!(@mountpoint)
      {_output, 0} = System.cmd("chattr", ["+i", @mountpoint])
    end

    Logger.info("[RemoteConfigurer] Add mountpoint to fstab and mount it")

    part = get_disk_first_part(drive.path)
    :ok = ExNVR.Nerves.DiskMounter.add_fstab_entry(part.fs.uuid, @mountpoint, :ext4)
end
```

After creating the admin user and configuring the Grafana agent, device details are sent back to the server and the configuration file is created:

```elixir
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
```
