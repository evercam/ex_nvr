defmodule ExNVR.Devices do
  @moduledoc """
  Context to manipulate devices
  """

  alias ExNVR.Model.Device
  alias ExNVR.Repo

  @spec create(map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    params
    |> Device.create_changeset()
    |> Repo.insert()
  end

  @spec list() :: [Device.t()]
  def list(), do: Repo.all(Device)
end
