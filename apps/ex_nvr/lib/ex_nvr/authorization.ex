defmodule ExNVR.Authorization do
  @moduledoc """
  Basic user authorization module by role.
  """
  alias ExNVR.Accounts.User
  def authorize(%User{role: :admin}, _resource, _action), do: :ok
  def authorize(%User{role: :user}, _resource, :read), do: :ok
  def authorize(_user, _resource, _action), do: {:error, :unauthorized}
end
