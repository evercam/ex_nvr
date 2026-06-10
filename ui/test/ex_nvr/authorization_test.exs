defmodule ExNVR.AuthorizationTest do
  use ExUnit.Case, async: true

  alias ExNVR.Accounts.User
  alias ExNVR.Authorization

  # Resources and actions used across the codebase, plus an arbitrary
  # atom for each to make sure the policy doesn't depend on a fixed list.
  @restricted_resources [:user, :system]
  @other_resources [:device, :onvif, :remote_storage, :trigger, :other_resource]
  @resources @restricted_resources ++ @other_resources

  @read_action :read
  @non_read_actions [:create, :update, :delete, :any, :discover, :other_action]
  @actions [@read_action | @non_read_actions]

  describe "authorize/3 with an admin user" do
    test "allows any action on any resource" do
      admin = %User{role: :admin}

      for resource <- @resources, action <- @actions do
        assert Authorization.authorize(admin, resource, action) == :ok,
               "expected admin to be authorized for #{inspect(action)} on #{inspect(resource)}"
      end
    end
  end

  describe "authorize/3 with a regular user" do
    setup do
      %{user: %User{role: :user}}
    end

    test "denies any action on restricted resources", %{user: user} do
      for resource <- @restricted_resources, action <- @actions do
        assert Authorization.authorize(user, resource, action) == {:error, :unauthorized},
               "expected user to be denied #{inspect(action)} on #{inspect(resource)}"
      end
    end

    test "allows :read on unrestricted resources", %{user: user} do
      for resource <- @other_resources do
        assert Authorization.authorize(user, resource, @read_action) == :ok,
               "expected user to be authorized to read #{inspect(resource)}"
      end
    end

    test "denies non-read actions on unrestricted resources", %{user: user} do
      for resource <- @other_resources, action <- @non_read_actions do
        assert Authorization.authorize(user, resource, action) == {:error, :unauthorized},
               "expected user to be denied #{inspect(action)} on #{inspect(resource)}"
      end
    end
  end

  describe "authorize/3 with unexpected input" do
    test "denies a nil user" do
      for resource <- @resources, action <- @actions do
        assert Authorization.authorize(nil, resource, action) == {:error, :unauthorized}
      end
    end

    test "denies a user with an unknown role" do
      # Not representable through changesets (role is an Ecto.Enum of
      # [:admin, :user]) but possible when building the struct directly.
      for role <- [:superadmin, :guest, "admin"], resource <- @resources, action <- @actions do
        user = %User{role: role}

        assert Authorization.authorize(user, resource, action) == {:error, :unauthorized},
               "expected role #{inspect(role)} to be denied #{inspect(action)} on #{inspect(resource)}"
      end
    end

    test "denies a user with a nil role" do
      for resource <- @resources, action <- @actions do
        assert Authorization.authorize(%User{role: nil}, resource, action) ==
                 {:error, :unauthorized}
      end
    end

    test "denies non-User terms even when they carry an admin role" do
      for subject <- [%{role: :admin}, :admin, {:user, :admin}] do
        assert Authorization.authorize(subject, :device, :read) == {:error, :unauthorized}
      end
    end
  end
end
