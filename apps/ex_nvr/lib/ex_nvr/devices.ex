defmodule ExNVR.Devices do
  @moduledoc """
  Context to manipulate devices
  """

  alias Ecto.Multi
  alias ExNVR.Model.{Device, Recording, Run}
  alias ExNVR.{Repo, DeviceSupervisor}
  alias Ecto.Multi

  import Ecto.Query

  @spec create(map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    Multi.new()
    |> Multi.insert(:device, Device.create_changeset(params))
    |> Multi.run(:create_directories, fn _repo, %{device: device} ->
      create_device_directories(device)
      copy_device_file(device)
      {:ok, nil}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{device: device}} -> {:ok, device}
      {:error, :device, changeset, _} -> {:error, changeset}
    end
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

  @spec delete(Device.t()) ::
          :ok | {:error, Ecto.Changeset.t()}
  def delete(device) do
    Multi.new()
    |> Multi.delete_all(:recordings, Recording.with_device(device.id))
    |> Multi.delete_all(:runs, Run.with_device(device.id))
    |> Multi.delete(:device, device)
    |> Multi.run(:stop_pipeline, fn _repo, _param ->
      DeviceSupervisor.stop(device)
      {:ok, nil}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} -> :ok
      {:error, _, changeset, _} -> {:error, changeset}
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

  defp create_device_directories(device) do
    File.mkdir_p!(Device.base_dir(device))
    File.mkdir_p!(Device.recording_dir(device))
    File.mkdir_p!(Device.recording_dir(device, :low))
    File.mkdir_p!(Device.bif_dir(device))
  end

  defp copy_device_file(%Device{type: :file, stream_config: stream_config} = device) do
    File.cp!(stream_config.temporary_path, Device.file_location(device))
  end

  defp copy_device_file(_device), do: :ok
end
