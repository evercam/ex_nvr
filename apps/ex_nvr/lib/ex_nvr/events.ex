defmodule ExNVR.Events do
  alias ExNVR.Model.{Device, Event}
  alias Ecto.Multi
  alias ExNVR.Repo

  def create(params, device, "lpr") do
    formated_event =
      params
      |> rename_milesight_keys(device)
      |> Map.put(:type, "lpr")
      |> Map.put(:device_id, device.id)

    Multi.new()
    |> Multi.insert(:event, Event.changeset(formated_event))
    |> Multi.run(:create_thumbnail, fn _repo, %{event: event} ->
      event
      |> base_dir(device)
      |> tap(&File.mkdir_p!/1)
      |> Path.join("#{event.plate_number}_#{event.id}.jpg")
      |> File.write!(Base.decode64!(params["plate_image"]))

      {:ok, nil}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event}} -> {:ok, event}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def create(_, _, _), do: {:error, "Event type isn't supported"}

  @spec base_dir(Event.t(), Device.t()) :: binary()
  def base_dir(event, device) do
    device
    |> Device.base_dir()
    |> Path.join("thumbnails")
    |> Path.join(event.type)
  end

  defp rename_milesight_keys(entry, %Device{timezone: timezone}) do
    %{
      capture_time:
        entry
        |> Map.get("time", "")
        |> String.split(" ")
        |> parse_capture_time(timezone),
      plate_number: entry["plate"],
      direction: entry["direction"]
    }
  end

  defp parse_capture_time([date, time], timezone) do
    DateTime.new!(
      Date.from_iso8601!(date),
      Time.from_iso8601!(time),
      timezone
    )
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp parse_capture_time(_, _), do: nil
end
