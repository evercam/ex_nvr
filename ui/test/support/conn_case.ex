defmodule ExNVRWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ExNVRWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint ExNVRWeb.Endpoint

      use ExNVRWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import ExNVRWeb.ConnCase

      import ExNVR.DevicesFixtures
    end
  end

  setup tags do
    ExNVR.DataCase.setup_sandbox(tags)
    maybe_set_application_env(tags)

    Map.put(
      maybe_create_device(tags),
      :conn,
      Phoenix.ConnTest.build_conn()
    )
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = ExNVR.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user) do
    token = ExNVR.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  def log_in_user_with_access_token(conn, user) do
    token = ExNVR.Accounts.generate_user_access_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  def maybe_create_device(tags) do
    if Map.has_key?(tags, :device) do
      device = ExNVR.DevicesFixtures.camera_device_fixture(tags[:tmp_dir])
      %{device: device}
    else
      %{}
    end
  end

  defp maybe_set_application_env(tags) do
    if Map.has_key?(tags, :tmp_dir) do
      Application.put_env(:ex_nvr, :hls_directory, tags.tmp_dir)
    end
  end
end
