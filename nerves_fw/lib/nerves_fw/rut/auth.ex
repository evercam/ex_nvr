defmodule ExNVR.Nerves.RUT.Auth do
  @moduledoc false
  require Logger

  use GenServer

  @login_path "/api/login"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_client(timeout \\ 5000) do
    GenServer.call(__MODULE__, :get_client, timeout)
  end

  @impl true
  def init(opts) do
    settings = ExNVR.Nerves.SystemSettings.get_settings()

    state = %{
      username: settings[:router_username],
      password: settings[:router_password],
      client: nil,
      refresh_timer: nil
    }

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
  def handle_info(:refresh, %{client: client} = state) do
    Logger.info("[RUT] Refresh auth token")

    case refresh?(client) |> IO.inspect() do
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
      {:ok, %Req.Response{status: 200, body: body}} ->
        {token, expires_in, legacy} =
          case body do
            %{"jwtToken" => token} -> {token, body["expires"], true}
            %{"ubus_rpc_session" => token} -> {token, body["expires"], true}
            %{"data" => data} -> {data["token"], data["expires"], false}
          end

        req =
          Req.new(base_url: base_url <> "/api", auth: {:bearer, token})
          |> Req.Request.put_private(:legacy, legacy)

        {:ok, req, expires_in}

      {:ok, %Req.Response{body: body}} ->
        {:error, body["errors"]}

      other ->
        other
    end
  end

  defp refresh?(client) do
    url =
      case Req.Request.get_private(client, :legacy) do
        false -> "/session/status"
        true -> "/system/device/status"
      end

    case Req.get(client, url: url) do
      {:ok, %{body: %{"success" => true}}} -> true
      _other -> false
    end
  end
end
