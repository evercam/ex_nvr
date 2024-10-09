defmodule ExNVR.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Membrane.Logger

  @cert_file_path "priv/integrated_turn_cert.pem"

  @impl true
  def start(_type, _args) do
    children = [
      ExNVR.Repo,
      ExNVR.TokenPruner,
      {Phoenix.PubSub, name: ExNVR.PubSub},
      {Finch, name: ExNVR.Finch},
      {Task.Supervisor, name: ExNVR.TaskSupervisor},
      {DynamicSupervisor, [name: ExNVR.PipelineSupervisor, strategy: :one_for_one]},
      Task.child_spec(fn -> ExNVR.start() end)
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExNVR.Supervisor)
  end

  @impl true
  def stop(_state) do
    delete_cert_file()
    :ok
  end

  defp delete_cert_file(), do: File.rm(@cert_file_path)
end
