defmodule ExNVR.Triggers.Listener do
  @moduledoc """
  GenServer that subscribes to event broadcasts and evaluates triggers.
  """

  use GenServer

  require Logger

  alias ExNVR.Triggers

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExNVR.PubSub, Triggers.events_topic())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:event_created, event}, state) do
    Triggers.Executor.evaluate(event)
    {:noreply, state}
  rescue
    e ->
      Logger.error("Trigger listener error: #{Exception.message(e)}")
      {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
