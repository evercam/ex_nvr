defmodule ExNVR.Recordings.Export do
  @moduledoc """
    This module contains func for grouping samples into chunks of 1 hr, 
    exporting them to destination(removable device)
    
  """

  alias ExNVR.Recordings.VideoAssembler
  alias ExNVR.Recordings
  alias ExNVR.Model.{Device, Recording}

  use GenServer

  @type export_type() :: :full | :one

  @spec export_to_usb(
          export_type(),
          Device.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: :ok
  def export_to_usb(:full, device, start_date, end_date, dest) do
    rec =
      Recordings.get_recordings_between(device.id, start_date, end_date)

    {:ok, start_date, _} = DateTime.from_iso8601(start_date <> ":00Z")
    {:ok, end_date, _} = DateTime.from_iso8601(end_date <> ":00Z")

    number_of_rec = Recordings.count_number_of_recordings(device.id, :high, start_date, end_date)

    copy_to_usb(device, start_date, end_date, dest, number_of_rec, 50, false)
  end

  def export_to_usb(:one, device, start_date, end_date, dest) do
    Recordings.get_recordings_between(device.id, start_date, end_date)
    |> Enum.map(fn rec ->
      System.cmd("cp", [
        "#{Recordings.recording_path(device, rec.stream, rec)}",
        "#{dest}/#{format_date(rec.start_date)}_to_#{format_date(rec.end_date)}"
      ])
    end)
  end

  # when you search recordings to databases they come in a default limit of 50

  def copy_to_usb(device, start_date, end_date, dest, number_of_rec, limit, done)
      when done == false do
    Recordings.get_recordings_between(device.id, start_date, end_date)
    |> case do
      [] ->
        copy_to_usb(
          device,
          start_date,
          end_date,
          dest,
          number_of_rec,
          limit,
          true
        )

      rec ->
        new_dest =
          (dest <>
             "/rec_#{start_date}_to_#{end_date}.mp4")
          |> String.replace(":", "-")

        start_date =
          if start_date != nil && is_binary(start_date) do
            {:ok, start_date, _} = DateTime.from_iso8601(start_date)
            start_date
          else
            start_date
          end

        VideoAssembler.assemble(device, :high, start_date, end_date, 3_600, new_dest)

        start_date =
          List.last(rec).end_date
          |> DateTime.to_string()

        # the number of recordings == real number - limit, 50, to get the percentage download
        percentage =
          (limit / number_of_rec * 100)
          |> min(100)

        Phoenix.PubSub.broadcast(
          ExNVR.PubSub,
          "export_notifacation",
          {:progress, %{export_progress_percentage: round(percentage)}}
        )

        copy_to_usb(
          device,
          start_date,
          end_date,
          dest,
          number_of_rec,
          limit + 50,
          false
        )
    end
  end

  def copy_to_usb(_device, _start_date, _end_date, _dest, _number_of_rec, _limit, done)
      when done == true,
      do: :ok

  def copy(device, start_date, end_date) do
    rec =
      Recordings.get_recordings_between(device.id, start_date, end_date)

    # perform the export operations

    start_date = List.last(rec).end_date

    copy(device, start_date, end_date)
  end

  @spec copy(
          Device.t(),
          [Recording.t()],
          non_neg_integer(),
          non_neg_integer(),
          String.t(),
          non_neg_integer()
        ) :: :ok
  defp copy(device, rec, start, finish, dest, counter)
       when finish <= length(rec) do
    start_date = Enum.at(rec, start).start_date

    end_date =
      Enum.at(rec, finish - 1).end_date

    new_dest =
      (dest <> "/rec_#{DateTime.to_string(start_date)}_to_#{DateTime.to_string(end_date)}.mp4")
      |> String.replace(":", "-")

    rec_length =
      rec
      |> Enum.chunk_every(finish)
      |> length()

    finished_date =
      VideoAssembler.assemble(device, :high, start_date, end_date, 3_600, new_dest)

    Phoenix.PubSub.broadcast(
      ExNVR.PubSub,
      "export_notifacation",
      {:progress, %{percentage: counter / rec_length * 100, finished_date: finished_date}}
    )

    counter = counter + 1
    copy(device, rec, start + finish + 1, finish + 20, dest, counter + 1)
  end

  defp copy(_device, rec, _start, finish, _dest, _counter)
       when finish > length(rec),
       do: :ok

  @spec format_date(String.t() | Date.t()) :: String.t()
  defp format_date(date) when is_binary(date) do
    date
    |> String.replace(":", "-")
  end

  defp format_date(date) do
    date
    |> DateTime.to_string()
    |> format_date()
  end
end
