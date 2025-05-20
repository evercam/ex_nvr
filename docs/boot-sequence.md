# Boot Sequence

This guide describes how ExNVR boots on embedded targets.

## Erlinit and Shoehorn

`erlinit` starts the BEAM VM and `shoehorn` ensures that `:nerves_runtime` and `:nerves_pack` are launched before the main application. This is configured in `config/target.exs`.

## Application Startup

`ExNVR.Nerves.Application.start/2` runs database migrations and then starts the supervision tree based on the current target:

```elixir
@impl true
def start(_type, _args) do
  opts = [strategy: :one_for_one, name: ExNVR.Nerves.Supervisor]

  children = [] ++ children(target())

  ExNVR.Release.migrate()

  Supervisor.start_link(children, opts)
end
```

For the `:giraffe` target a hardware initializer powers the HDD and PoE, otherwise the power monitoring process is started:

```elixir
def children(:giraffe) do
  [{ExNVR.Nerves.Giraffe.Init, []}] ++ common_config()
end

def children(_target) do
  DynamicSupervisor.start_child(ExNVR.Hardware.Supervisor, {ExNVR.Nerves.Hardware.Power, []})
  common_config()
end
```

## Common Services

Regardless of target the following children are started:

```elixir
defp common_config() do
  [
    {ExNVR.Nerves.Netbird, []},
    {ExNVR.Nerves.DiskMounter, []},
    {ExNVR.Nerves.GrafanaAgent, grafana_agent_config()},
    {MuonTrap.Daemon, ["nginx", [], [stderr_to_stdout: true, log_output: :info]]},
    {ExNVR.Nerves.RemoteConfigurer, Application.get_env(:ex_nvr_fw, :remote_configurer)},
    {ExNVR.Nerves.SystemStatus, []},
    {ExNVR.Nerves.Monitoring.PowerSchedule, []},
    {ExNVR.Nerves.RUT.Auth, []}
  ]
end
```

See `docs/system-processes.md` for an overview of these services.
