defmodule ExNVR.Authorization do
  alias __MODULE__
  alias ExNVR.Model.{Device, Recording}

  defstruct role: nil, create: %{}, read: %{}, update: %{}, delete: %{}, stream: %{}, download_archives: %{}

  def can(:admin = role) do
    grant(role)
    |> all(Device)
    |> all(Recording)
  end

  def can(:user = role) do
    grant(role)
    |> edit(Device)
    |> read(Recording)
  end

  def grant(role), do: %Authorization{role: role}

  def read(authorization, resource), do: put_action(authorization, :read, resource)

  def create(authorization, resource), do: put_action(authorization, :create, resource)

  def update(authorization, resource), do: put_action(authorization, :update, resource)

  def delete(authorization, resource), do: put_action(authorization, :delete, resource)

  def stream(authorization, resource), do: put_action(authorization, :stream, resource)

  def download_archives(authorization, resource), do: put_action(authorization, :download_archives, resource)

  def edit(authorization, resource) do
    authorization
    |> create(resource)
    |> read(resource)
    |> update(resource)
  end

  def all(authorization, resource) do
    authorization
    |> edit(resource)
    |> delete(resource)
    |> stream(resource)
    |> download_archives(resource)
  end

  def read?(authorization, resource) do
    Map.get(authorization.read, resource, false)
  end

  def create?(authorization, resource) do
    Map.get(authorization.create, resource, false)
  end

  def update?(authorization, resource) do
    Map.get(authorization.update, resource, false)
  end

  def delete?(authorization, resource) do
    Map.get(authorization.delete, resource, false)
  end

  def stream?(authorization, resource) do
    Map.get(authorization.stream, resource, false)
  end

  def download_archives?(authorization, resource) do
    Map.get(authorization.download_archives, resource, false)
  end

  defp put_action(authorization, action, resource) do
    updated_action =
      authorization
      |> Map.get(action)
      |> Map.put(resource, true)

    Map.put(authorization, action, updated_action)
  end

end
