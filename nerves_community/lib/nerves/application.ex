defmodule ExNVR.Nerves.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
      ] ++ target_children()

    ExNVR.Release.migrate()
    ExNVR.start()

    opts = [strategy: :one_for_one, name: ExNVR.Nerves.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  if Mix.target() == :host do
    defp target_children() do
      []
    end
  else
    defp target_children() do
      [{ExNVR.Nerves.DiskMounter, []}]
    end
  end
end
