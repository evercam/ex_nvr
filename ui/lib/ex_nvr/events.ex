defmodule ExNVR.Events do
  @moduledoc false

  import Ecto.Query

  alias ExNVR.Events.{Event, LPR}
  alias ExNVR.Model.Device
  alias ExNVR.Repo

  @type flop_result :: {:ok, {[map()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}

  @spec create_event(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def create_event(params) do
    do_create_event(nil, params)
  end

  @spec create_event(Device.t(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def create_event(device, params) do
    do_create_event(device.id, params)
  end

  @spec create_lpr_event(Device.t(), map(), binary() | nil) ::
          {:ok, LPR.t()} | {:error, Ecto.Changeset.t()}
  def create_lpr_event(device, params, plate_picture) do
    insertion_result =
      params
      |> Map.put(:device_id, device.id)
      |> LPR.changeset()
      |> Repo.insert(on_conflict: :nothing)

    with {:ok, %{id: id} = event} when not is_nil(id) <- insertion_result do
      if plate_picture do
        device
        |> Device.lpr_thumbnails_dir()
        |> tap(&File.mkdir/1)
        |> Path.join(LPR.plate_name(event))
        |> File.write(plate_picture)
      end

      {:ok, event}
    end
  end

  @spec list_events(map()) :: flop_result()
  def list_events(%Flop{} = flop) do
    Event |> preload([:device]) |> ExNVR.Flop.validate_and_run(flop)
  end

  @spec list_events(map()) :: flop_result()
  def list_events(params) do
    Event
    |> preload([:device])
    |> Event.filter(params)
    |> ExNVR.Flop.validate_and_run(params, for: Event)
  end

  @spec list_lpr_events(map(), Keyword.t()) :: flop_result()
  def list_lpr_events(params, opts \\ []) do
    LPR
    |> preload([:device])
    |> ExNVR.Flop.validate_and_run(params, for: LPR)
    |> case do
      {:ok, {data, meta}} ->
        {:ok, {maybe_include_lpr_thumbnails(opts[:include_plate_image], data), meta}}

      other ->
        other
    end
  end

  @spec get_event(integer()) :: Event.t() | nil
  def get_event(id) do
    Repo.get(Event, id)
    |> Repo.preload(:device)
  end

  @spec last_lpr_event_timestamp(Device.t()) :: DateTime.t() | nil
  def last_lpr_event_timestamp(device) do
    LPR
    |> select([e], e.capture_time)
    |> where([e], e.device_id == ^device.id)
    |> order_by(desc: :capture_time)
    |> limit(1)
    |> Repo.one()
  end

  @spec lpr_event_thumbnail(LPR.t()) :: binary() | nil
  def lpr_event_thumbnail(lpr_event) do
    ExNVR.Model.Device.lpr_thumbnails_dir(lpr_event.device)
    |> Path.join(LPR.plate_name(lpr_event))
    |> File.read()
    |> case do
      {:ok, image} -> Base.encode64(image)
      _other -> nil
    end
  end

  defp do_create_event(device_id, params) do
    %Event{device_id: device_id}
    |> Event.changeset(params)
    |> Repo.insert()
  end

  defp maybe_include_lpr_thumbnails(true, entries) do
    Enum.map(entries, fn entry ->
      plate_image = lpr_event_thumbnail(entry)
      Map.put(entry, :plate_image, plate_image)
    end)
  end

  defp maybe_include_lpr_thumbnails(_other, entries), do: entries
end
