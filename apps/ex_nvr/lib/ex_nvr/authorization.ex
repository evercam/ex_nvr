defmodule ExNVR.Authorization do
  @moduledoc """
  Basic user authorization module by role.
  """
  alias ExNVR.Accounts.User
  def authorized?(%User{role: :admin}, _resource, _action), do: :ok
  def authorized?(%User{role: :user}, _resource, :read), do: :ok
  def authorized?(_user, _resource, _action), do: {:error, :unauthorized}
end
