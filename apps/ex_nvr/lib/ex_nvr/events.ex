defmodule ExNVR.Events do
  @moduledoc false

  alias ExNVR.Events.LPR
  alias ExNVR.Model.Device
  alias ExNVR.Repo

  @spec create_lpr_event(Device.t(), map(), binary() | nil) ::
          {:ok, LPR.t()} | {:error, Ecto.Changeset.t()}
  def create_lpr_event(device, params, plate_picture) do
    params
    |> Map.put(:device_id, device.id)
    |> LPR.changeset()
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        device
        |> Device.lpr_thumbnails_dir()
        |> Path.join(LPR.plate_name(event))
        |> File.write(plate_picture)

        {:ok, event}

      error ->
        error
    end
  end

  @spec list_lpr_events(map()) :: {:ok, {[map()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_lpr_events(params) do
    LPR.list_with_device()
    |> ExNVR.Flop.validate_and_run(params, for: LPREvent)
  end

  @spec list(binary(), atom()) :: [LPREvent.t()]
  def list(device_id, :lpr) do
    LPR.with_device(device_id)
    |> Repo.all()
  end
end
