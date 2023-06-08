defmodule ExNVR.Devices do
  @moduledoc """
  Context to manipulate devices
  """

  alias ExNVR.Model.Device
  alias ExNVR.Repo

  import Ecto.Query

  @spec create(map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    %Device{}
    |> Device.create_changeset(params)
    |> Repo.insert()
  end

  @spec list() :: [Device.t()]
  def list(), do: Repo.all(from(d in Device, order_by: d.id))

  @spec get(binary()) :: Device.t() | nil
  def get(device_id), do: Repo.get(Device, device_id)

  @spec change_device_creation(Device.t()) :: Ecto.Changeset.t()
  def change_device_creation(%Device{} = device, attrs \\ %{}) do
    Device.create_changeset(device, attrs)
  end
end
