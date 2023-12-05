defmodule ExNVR.Authorization do
  @moduledoc """
  Basic user authorization module by role.
  """
  def is_authorized?(:admin, :device, _action), do: true
  def is_authorized?(:user, :device, :read), do: true
  def is_authorized?(_role, :recording, :read), do: true

  def is_authorized?(_role, _resource, _action), do: false
end
