defmodule ExNVR.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ExNVR.Repo,
      {Phoenix.PubSub, name: ExNVR.PubSub},
      {Finch, name: ExNVR.Finch},
      {DynamicSupervisor, [name: ExNVR.PipelineSupervisor, strategy: :one_for_one]},
      Task.child_spec(fn -> ExNVR.start() end)
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExNVR.Supervisor)
  end
end
