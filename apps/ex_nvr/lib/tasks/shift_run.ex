defmodule ExNVR.Tasks.ShiftRun do
  @moduledoc """
  Shift the run and all its recordings by a specific period.
  """

  require Logger

  alias ExNVR.Model.{Recording, Run}

  @camera_clock_correction 30_000

  @spec shift_by(non_neg_integer(), microsecond :: integer(), boolean()) :: :ok
  def shift_by(run_id, duration, add_correction \\ false) do
    run = ExNVR.Repo.get!(Run, run_id)
    device = ExNVR.Devices.get!(run.device_id)

    {end_date, _duration} =
      list_recordings(run)
      |> Enum.reduce({nil, duration}, fn recording, {_last_date, duration} ->
        new_rec = update_recording(recording, device, duration, add_correction)

        new_duration =
          cond do
            add_correction and duration >= 0 ->
              max(duration - @camera_clock_correction, 0)

            add_correction and duration < 0 ->
              min(duration + @camera_clock_correction, 0)

            true ->
              duration
          end

        {new_rec.end_date, new_duration}
      end)

    params = %{
      start_date: DateTime.add(run.start_date, duration, :microsecond),
      end_date: end_date
    }

    ExNVR.Repo.update!(Run.changeset(run, params))
  end

  defp list_recordings(run) do
    do_list_recordings(run.start_date, [])
  end

  defp do_list_recordings(start_date, recordings) do
    if rec = ExNVR.Repo.get_by(Recording, start_date: start_date) do
      do_list_recordings(rec.end_date, [rec | recordings])
    else
      Enum.reverse(recordings)
    end
  end

  defp update_recording(rec, device, duration, add_correction) do
    start_date = DateTime.add(rec.start_date, duration, :microsecond)
    end_date = DateTime.add(rec.end_date, duration, :microsecond)

    changeset =
      Ecto.Changeset.change(
        rec,
        %{
          start_date: start_date,
          end_date: end_date,
          filename: "#{DateTime.to_unix(start_date, :microsecond)}.mp4"
        }
      )

    new_rec = ExNVR.Repo.update!(changeset)

    File.rename(
      ExNVR.Recordings.recording_path(device, rec),
      ExNVR.Recordings.recording_path(device, new_rec)
    )

    new_rec
  end
end
