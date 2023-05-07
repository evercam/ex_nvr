defmodule ExNVR.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      ExNVR.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: ExNVR.PubSub},
      # Start Finch
      {Finch, name: ExNVR.Finch}
      # Start a worker by calling: ExNVR.Worker.start_link(arg)
      # {ExNVR.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExNVR.Supervisor)
  end
end
