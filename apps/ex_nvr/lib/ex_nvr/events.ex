defmodule ExNVR.Events do
  alias Membrane.Event
  alias ExNVR.Model.{Device, LPREvent}
  alias ExNVR.Repo

  @spec create_lpr_event(Device.t(), map(), binary() | nil, binary() | nil) ::
          {:ok, LPREvent.t()} | {:error, Ecto.Changeset.t()}
  def create_lpr_event(device, params, plate_picture \\ nil, full_picture \\ nil) do
    params
    |> Map.put(:device_id, device.id)
    |> LPREvent.changeset()
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        event = Repo.preload(event, :device)

        event
        |> lpr_event_filename()
        |> save_image(plate_picture)

        event
        |> lpr_event_filename("full_picture")
        |> save_image(full_picture)

        {:ok, event}

      error ->
        error
    end
  end

  @spec list_lpr_events(map()) :: {:ok, {[map()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_lpr_events(params) do
    LPREvent.list_with_device()
    |> ExNVR.Flop.validate_and_run(params, for: LPREvent)
  end

  @spec list(binary(), atom()) :: [LPREvent.t()]
  def list(device_id, :lpr) do
    LPREvent.with_device(device_id)
    |> Repo.all()
  end

  @spec lpr_event_filename(Event.t(), binary()) :: binary()
  def lpr_event_filename(event, suffix \\ "thumbnails") do
    event.device
    |> Device.lpr_dir(suffix)
    |> Path.join("#{event.plate_number}_#{event.id}.jpg")
  end

  defp save_image(_, nil), do: nil

  defp save_image(path, image) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, image)
  end
end
