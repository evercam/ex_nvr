defmodule ExNVR.Recordings.Export do
  @moduledoc """
    This module contains func for grouping samples into chunks of 1 hr, 
    ability to know which chuck has not been copied yet
    report a progress ar when copying to external usb
    
    fetch the recordings from that date
    group them by sixy times
    
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
    # list of map
    rec =
      Recordings.get_recordings_between(device.id, start_date, end_date)

    rec
    |> Enum.chunk_every(40)
    |> length()

    start = 0
    finish = if length(rec) < 60, do: length(rec), else: 60

    copy(device, rec, start, finish, dest, 1)
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

    dest =
      dest <> "/rec_#{DateTime.to_string(start_date)}_to_#{DateTime.to_string(end_date)}.mp4"

    rec_length =
      rec
      |> Enum.chunk_every(finish)
      |> length()

    finished_date =
      VideoAssembler.assemble(device, :high, start_date, end_date, 3_600, dest)

    Phoenix.PubSub.broadcast(
      ExNVR.PubSub,
      "export_notifacation",
      {:progress, %{percentage: counter / rec_length * 100, finished_date: finished_date}}
    )

    counter = counter + 1
    copy(device, rec, start + finish + 1, finish + 60, dest, counter)
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
