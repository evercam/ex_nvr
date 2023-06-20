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

  @spec update(Device.t(), map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update(%Device{} = device, params) do
    device
    |> Device.update_changeset(params)
    |> Repo.update()
  end

  @spec update_state(Device.t(), Device.state()) ::
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update_state(%Device{} = device, state), do: __MODULE__.update(device, %{state: state})

  @spec list(map()) :: [Device.t()]
  def list(params \\ %{}), do: Repo.all(Device.filter(params) |> order_by([d], d.inserted_at))

  @spec get(binary()) :: Device.t() | nil
  def get(device_id), do: Repo.get(Device, device_id)

  @spec get!(binary()) :: Device.t()
  def get!(device_id) do
    case get(device_id) do
      %Device{} = device -> device
      nil -> raise "device does not exists"
    end
  end

  @spec change_device_creation(Device.t(), map()) :: Ecto.Changeset.t()
  def change_device_creation(%Device{} = device, attrs \\ %{}) do
    Device.create_changeset(device, attrs)
  end

  @spec change_device_update(Device.t(), map()) :: Ecto.Changeset.t()
  def change_device_update(%Device{} = device, attrs \\ %{}) do
    Device.update_changeset(device, attrs)
  end
end
