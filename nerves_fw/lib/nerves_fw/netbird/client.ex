defmodule ExNVR.Nerves.Netbird.Client do
  @moduledoc false

  use GenServer

  @timeout :timer.minutes(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def up(management_url, setup_key, host) do
    GenServer.call(__MODULE__, {:up, management_url, setup_key, host}, @timeout)
  end

  def up() do
    GenServer.call(__MODULE__, :up, @timeout)
  end

  def down() do
    GenServer.call(__MODULE__, :down, @timeout)
  end

  def status() do
    GenServer.call(__MODULE__, :status, @timeout)
  end

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def handle_call({:up, management_url, setup_key, host}, _from, state) do
    args = ["up", "--management-url", management_url, "-k", setup_key] ++ common_args(state)
    args = if host, do: args ++ ["--hostname", host], else: args

    {:reply, run_cmd(args), state}
  end

  @impl true
  def handle_call(:up, _from, state) do
    args = ["up" | common_args(state)]
    {:reply, run_cmd(args), state}
  end

  @impl true
  def handle_call(:down, _from, state) do
    args = ["down" | common_args(state)]
    {:reply, run_cmd(args), state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    args = ["status", "--json" | common_args(state)]

    case run_cmd(args) do
      {:ok, output} ->
        result =
          case Jason.decode(output) do
            {:ok, json} -> {:ok, json}
            {:error, _error} -> {:error, :needs_login}
          end

        {:reply, result, state}

      error ->
        {:reply, error, state}
    end
  end

  defp common_args(state), do: ["--daemon-addr", state[:daemon_addr]]

  defp run_cmd(args) do
    case System.cmd("netbird", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {err, code} -> {:error, err, code}
    end
  end
end
