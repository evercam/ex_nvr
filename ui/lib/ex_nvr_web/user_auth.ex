defmodule ExNVRWeb.UserAuth do
  use ExNVRWeb, :verified_routes

  require Logger

  import ExNVRWeb.Controller.Helpers
  import Plug.Conn
  import Phoenix.Controller

  alias ExNVR.Accounts

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 15
  @remember_me_cookie "_ex_nvr_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      ExNVRWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, context, conn} = ensure_user_token(conn)
    user = fetch_user_by_token(user_token, context)

    if user, do: Logger.metadata(user_id: user.id)

    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    cond do
      token = get_session(conn, :user_token) ->
        {token, "session", conn}

      token = fetch_token_from_headers_or_query_params(conn) ->
        {token, "access", conn}

      true ->
        conn = fetch_cookies(conn, signed: [@remember_me_cookie])

        if token = conn.cookies[@remember_me_cookie] do
          {token, "session", put_token_in_session(conn, token)}
        else
          {nil, "session", conn}
        end
    end
  end

  defp fetch_token_from_headers_or_query_params(conn, query_name \\ "access_token") do
    if token = fetch_from_headers(conn),
      do: token,
      else: fetch_from_query_params(conn, query_name)
  end

  defp fetch_from_headers(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
    |> case do
      nil -> nil
      token -> String.trim_leading(token, "Bearer ") |> decode_access_token()
    end
  end

  defp fetch_from_query_params(%{query_params: query_params}, query_name),
    do: decode_access_token(query_params[query_name])

  defp fetch_user_by_token(nil, _context), do: nil
  defp fetch_user_by_token(token, "session"), do: Accounts.get_user_by_session_token(token)
  defp fetch_user_by_token(token, "access"), do: Accounts.get_user_by_access_token(token)

  defp decode_access_token(nil), do: nil

  defp decode_access_token(token) do
    case Base.url_decode64(token) do
      {:ok, decoded_token} -> decoded_token
      _ -> nil
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `:redirect_if_user_is_authenticated` - Authenticates the user from the session.
      Redirects to signed_in_path if there's a logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule ExNVRWeb.PageLive do
        use ExNVRWeb, :live_view

        on_mount {ExNVRWeb.UserAuth, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{ExNVRWeb.UserAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(session, socket)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(session, socket)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/login")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(session, socket)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  def on_mount(:ensure_user_is_admin, _params, _session, socket) do
    if socket.assigns.current_user.role == :admin do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You can't access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/dashboard")

      {:halt, socket}
    end
  end

  defp mount_current_user(session, socket) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be an admin.
  """
  def require_admin_user(conn, _opts) do
    if conn.assigns[:current_user].role == :admin do
      conn
    else
      conn
      |> put_flash(:error, "You can't access this page.")
      |> redirect(to: ~p"/dashboard")
      |> halt()
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, api: true) do
    if conn.assigns[:current_user] do
      conn
    else
      unauthorized(conn)
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/login")
      |> halt()
    end
  end

  @doc """
  Used for routes that require a webhook token.
  """
  def require_webhook_token(conn, _opts) do
    token = fetch_token_from_headers_or_query_params(conn, "token")

    if token && Accounts.verify_webhook_token(token) do
      conn
    else
      unauthorized(conn)
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/dashboard"
end
