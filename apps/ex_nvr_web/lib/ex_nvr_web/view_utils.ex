defmodule ExNVRWeb.ViewUtils do
  @moduledoc false

  @spec humanize_duration(non_neg_integer()) :: String.t()
  def humanize_duration(duration_ms) do
    milliseconds = rem(duration_ms, 1000)
    seconds = rem(div(duration_ms, 1000), 60)
    minutes = rem(div(duration_ms, 60 * 1000), 60)
    hours = div(duration_ms, 60 * 60 * 1000)

    duration =
      [hours, minutes, seconds]
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.pad_leading(&1, 2, "0"))
      |> Enum.join(":")

    "#{duration}.#{String.pad_leading(to_string(milliseconds), 3, "0")}"
  end

  @spec humanize_size(non_neg_integer()) :: String.t()
  def humanize_size(size_bytes) do
    cond do
      size_bytes / 1_000_000_000 >= 1 -> "#{Float.round(size_bytes / 1024 ** 3, 2)} GiB"
      size_bytes / 1_000_000 >= 1 -> "#{Float.round(size_bytes / 1024 ** 2, 2)} MiB"
      size_bytes / 1_000 >= 1 -> "#{Float.round(size_bytes / 1024, 2)} KiB"
      true -> "#{size_bytes} B"
    end
  end

  @spec humanize_bitrate(non_neg_integer()) :: String.t()
  def humanize_bitrate(bitrate) do
    if bitrate >= 1000, do: "#{div(bitrate, 1000)} kbps", else: "#{bitrate} bps"
  end
end
