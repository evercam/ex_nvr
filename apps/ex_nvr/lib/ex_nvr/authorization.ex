defmodule ExNVR.Authorization do
  @moduledoc """
  Basic user authorization module by role.
  """
  alias ExNVR.Accounts.User
  def authorized?(%User{role: :admin}, :device, _action), do: {:ok, :authorized}
  def authorized?(%User{role: :user}, :device, :read), do: {:ok, :authorized}
  def authorized?(_user, :recording, :read), do: {:ok, :authorized}

  def authorized?(_user, _resource, _action), do: {:error, :unauthorized}
end
