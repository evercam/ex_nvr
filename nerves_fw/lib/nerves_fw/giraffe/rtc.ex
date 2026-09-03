defmodule ExNVR.Nerves.Giraffe.RTC do
  @moduledoc """
  MCP79410 real-time clock/calendar (RTCC) logic.
  """

  import Bitwise

  alias Circuits.I2C
  alias NervesTime.RealTimeClock.BCD

  @address 0x6F

  @reg_seconds 0x00
  @reg_minutes 0x01
  @reg_weekday 0x03

  # RTCSEC bit 7: oscillator start. Must be set for the clock to run.
  @st_bit 0x80
  # RTCWKDAY bit 3: enable switch-over to the backup battery on power loss.
  @vbaten_bit 0x08
  # RTCWKDAY bit 5: set by the chip while the oscillator is actually running.
  @oscrun_bit 0x20

  # MCP79410 stores a two-digit year; anchor it to the 2000s.
  @century 2000

  @type bus :: I2C.bus()

  @spec open(String.t()) :: {:ok, bus()} | {:error, term()}
  def open(bus_name), do: I2C.open(bus_name)

  @spec close(bus()) :: :ok
  def close(bus), do: I2C.close(bus)

  @doc """
  Read the current time from the RTC.
  """
  @spec get_time(bus()) :: {:ok, NaiveDateTime.t()} | {:error, term()}
  def get_time(bus) do
    with {:ok, <<sec, min, hour, _wkday, date, month, year>>} <-
           I2C.write_read(bus, @address, <<@reg_seconds>>, 7) do
      NaiveDateTime.new(
        @century + BCD.to_integer(year),
        BCD.to_integer(month &&& 0x1F),
        BCD.to_integer(date &&& 0x3F),
        BCD.to_integer(hour &&& 0x3F),
        BCD.to_integer(min &&& 0x7F),
        BCD.to_integer(sec &&& 0x7F)
      )
    end
  end

  @doc """
  Set the RTC to the given `NaiveDateTime` (interpreted as UTC).

  Enables backup-battery switch-over (VBATEN bit) so the clock keeps running
  while the board is powered off.
  """
  @spec set_time(bus(), NaiveDateTime.t()) :: :ok | {:error, term()}
  def set_time(bus, %NaiveDateTime{} = time) do
    calendar = <<
      @reg_minutes,
      BCD.from_integer(time.minute),
      BCD.from_integer(time.hour),
      BCD.from_integer(Date.day_of_week(time)) ||| @vbaten_bit,
      BCD.from_integer(time.day),
      BCD.from_integer(time.month),
      BCD.from_integer(rem(time.year, 100))
    >>

    with :ok <- stop_oscillator(bus),
         :ok <- I2C.write(bus, @address, calendar) do
      # Writing the seconds register last, with ST set, restarts the oscillator.
      I2C.write(bus, @address, <<@reg_seconds, BCD.from_integer(time.second) ||| @st_bit>>)
    end
  end

  @doc """
  Report whether the oscillator is currently running.
  """
  @spec oscillator_running?(bus()) :: {:ok, boolean()} | {:error, term()}
  def oscillator_running?(bus) do
    with {:ok, <<wkday>>} <- I2C.write_read(bus, @address, <<@reg_weekday>>, 1) do
      {:ok, (wkday &&& @oscrun_bit) != 0}
    end
  end

  @doc """
  Report whether backup-battery switch-over is enabled (VBATEN bit).
  """
  @spec battery_backup_enabled?(bus()) :: {:ok, boolean()} | {:error, term()}
  def battery_backup_enabled?(bus) do
    with {:ok, <<wkday>>} <- I2C.write_read(bus, @address, <<@reg_weekday>>, 1) do
      {:ok, (wkday &&& @vbaten_bit) != 0}
    end
  end

  defp stop_oscillator(bus), do: I2C.write(bus, @address, <<@reg_seconds, 0>>)
end
