defmodule ExNVR.Nerves.RUT.Auth do
  @moduledoc false
  require Logger

  use GenServer

  alias ExNVR.Nerves.SystemSettings

  @login_path "/api/login"
  @receive_timeout to_timeout(second: 10)
  @connect_timeout to_timeout(second: 4)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_client(timeout \\ to_timeout(second: 15)) do
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

  defp get_default_gateway do
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
    conn_opts = [transport_opts: [verify: :verify_none]]

    resp =
      Req.new(url: url)
      |> track_redirected()
      |> Req.post(
        json: %{username: username, password: password},
        connect_options: conn_opts,
        retry: false,
        receive_timeout: @receive_timeout,
        connect_options: [timeout: @connect_timeout]
      )

    case resp do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}} = resp}
      when is_map_key(data, "expires") ->
        req =
          Req.new(
            base_url: Map.get(resp.private, :final_url, base_url) <> "/api",
            auth: {:bearer, data["token"]},
            connect_options: conn_opts
          )

        {:ok, req, data["expires"]}

      {:ok, %Req.Response{body: body}} ->
        message = if is_map(body), do: body["errors"], else: body
        {:error, message}

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

  defp track_redirected(request, opts \\ []) do
    request
    |> Req.Request.register_options([:track_redirected])
    |> Req.Request.merge_options(opts)
    |> Req.Request.prepend_response_steps(track_redirected: &track_redirected_uri/1)
  end

  defp track_redirected_uri({request, response}) do
    {request, put_in(response.private[:final_url], URI.to_string(%{request.url | path: nil}))}
  end
end
