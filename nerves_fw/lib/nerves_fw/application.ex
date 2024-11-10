defmodule ExNVR.Nerves.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: ExNVR.Nerves.Supervisor]

    children = [] ++ children(target())

    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  def children(:host) do
    []
  end

  def children(_target) do
    [
      {ExNVR.Nerves.Netbird, []},
      {ExNVR.Nerves.DiskMounter, []}
    ]
  end

  def target() do
    Application.get_env(:ex_nvr_fw, :target)
  end
end
