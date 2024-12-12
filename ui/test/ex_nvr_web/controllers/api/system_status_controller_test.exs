defmodule ExNVRWeb.API.SystemStatusControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures

  describe "GET /api/system/status" do
    test "get system status", %{conn: conn} do
      conn
      |> log_in_user_with_access_token(user_fixture())
      |> get(~p"/api/system/status")
      |> json_response(200)
    end

    test "get system status with unauthorized role", %{conn: conn} do
      conn
      |> log_in_user_with_access_token(user_fixture(role: :user))
      |> get(~p"/api/system/status")
      |> json_response(403)
    end
  end
end
