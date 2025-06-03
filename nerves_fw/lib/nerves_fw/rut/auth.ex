defmodule ExNVR.Nerves.RUT.Auth do
  @moduledoc false
  require Logger

  use GenServer

  alias ExNVR.Nerves.SystemSettings

  @login_path "/api/login"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_client(timeout \\ 5000) do
    GenServer.call(__MODULE__, :get_client, timeout)
  end

  @impl true
  def init(_opts) do
    router_config = SystemSettings.get_settings().router

    state = %{
      username: router_config.username,
      password: router_config.password,
      client: nil,
      refresh_timer: nil
    }

    SystemSettings.subscribe()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_client, _from, %{client: nil} = state) do
    {state, reply} =
      case do_authenticate(state) do
        {:ok, client, expires_in} ->
          {:ok, ref} = :timer.send_interval(to_timeout(second: expires_in - 5), :refresh)
          state = %{state | client: client, refresh_timer: ref}
          {state, {:ok, client}}

        error ->
          {state, error}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call(:get_client, _from, %{client: client} = state) do
    {:reply, {:ok, client}, state}
  end

  @impl true
  def handle_info({:system_settings, :update}, state) do
    router = SystemSettings.get_settings().router
    {:noreply, %{state | username: router.username, password: router.password}}
  end

  @impl true
  def handle_info(:refresh, %{client: client} = state) do
    Logger.info("[RUT] Refresh auth token")

    case refresh?(client) do
      true ->
        {:noreply, state}

      false ->
        :timer.cancel(state.refresh_timer)
        {:noreply, %{state | client: nil, refresh_timer: nil}}
    end
  end

  defp do_authenticate(state) do
    with :ok <- check_credentials(state),
         {:ok, gateway} <- get_default_gateway() do
      authenticate("http://" <> gateway, state.username, state.password)
    end
  end

  defp check_credentials(state) do
    if not is_nil(state.username) and not is_nil(state.password),
      do: :ok,
      else: {:error, :no_credentials}
  end

  defp get_default_gateway() do
    case System.cmd("ip", ["route"], stderr_to_stdout: true) do
      {output, 0} ->
        String.split(output, "\n")
        |> Enum.find("", &String.starts_with?(&1, "default"))
        |> String.split(" ")
        |> case do
          ["default", "via", gateway | _rest] -> {:ok, gateway}
          _other -> {:error, :no_gateway}
        end

      {error, _exit_status} ->
        {:error, error}
    end
  end

  defp authenticate(base_url, username, password) do
    url = base_url <> @login_path

    case Req.post(url, json: %{username: username, password: password}) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} when is_map_key(data, "expires") ->
        req = Req.new(base_url: base_url <> "/api", auth: {:bearer, data["token"]})
        {:ok, req, data["expires"]}

      {:ok, %Req.Response{body: body}} ->
        {:error, body["errors"]}

      other ->
        other
    end
  end

  defp refresh?(client) do
    case Req.get(client, url: "/session/status") do
      {:ok, %{body: %{"success" => true}}} -> true
      _other -> false
    end
  end
end
