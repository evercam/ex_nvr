defmodule ExNVR.Nerves.Giraffe.Fan do
  @moduledoc """
  EMC2101 fan controller logic.

  Stateless functions operating on an open `Circuits.I2C` bus reference.
  """

  import Bitwise

  alias Circuits.I2C

  @address 0x4C

  @reg_internal_temp 0x00
  @reg_external_temp_msb 0x01
  @reg_status 0x02
  @reg_config 0x03
  @reg_forced_temp 0x0C
  @reg_external_temp_lsb 0x10
  @reg_tach_lsb 0x46
  @reg_tach_msb 0x47
  @reg_fan_config 0x4A
  @reg_fan_setting 0x4C
  @reg_lut_base 0x50

  @status_fault 0x04
  @config_alt_tch 0x04
  @fan_config_force 0x40
  @fan_config_prog 0x20
  @fan_setting_max 0x3F
  @lut_max_entries 8

  # RPM = @tach_constant / tach_count (EMC2101 datasheet, 2 pulses per revolution)
  @tach_constant 5_400_000

  @default_lookup_table [
    {30, 20},
    {40, 30},
    {50, 45},
    {60, 65},
    {70, 85},
    {80, 100}
  ]

  @type bus :: I2C.bus()
  @type lookup_table :: [{0..127, 0..100}]

  @spec default_lookup_table() :: lookup_table()
  def default_lookup_table, do: @default_lookup_table

  @spec max_entries() :: pos_integer()
  def max_entries, do: @lut_max_entries

  @spec open(String.t()) :: {:ok, bus()} | {:error, term()}
  def open(bus_name), do: I2C.open(bus_name)

  @spec temperatures(bus()) ::
          {:ok, %{internal: number(), external: number()}} | {:error, term()}
  def temperatures(bus) do
    with {:ok, internal} <- internal_temperature(bus),
         {:ok, external} <- read_external_temp(bus) do
      {:ok, %{internal: internal, external: external}}
    end
  end

  @spec internal_temperature(bus()) :: {:ok, integer()} | {:error, term()}
  def internal_temperature(bus) do
    with {:ok, <<temp::signed-8>>} <- I2C.write_read(bus, @address, <<@reg_internal_temp>>, 1) do
      {:ok, temp}
    end
  end

  @doc """
  Detect whether an external temperature diode is connected.

  The EMC2101 reports a diode fault in its status register when the external
  diode is open circuit (i.e. no sensor is wired up).
  """
  @spec external_sensor?(bus()) :: {:ok, boolean()} | {:error, term()}
  def external_sensor?(bus) do
    with {:ok, <<status::8>>} <- I2C.write_read(bus, @address, <<@reg_status>>, 1) do
      {:ok, (status &&& @status_fault) == 0}
    end
  end

  @doc """
  Read the current fan speed in RPM.

  A stalled or disconnected fan reports a tach count of `0xFFFF`, which maps to
  0 RPM.
  """
  @spec speed(bus()) :: {:ok, non_neg_integer()} | {:error, term()}
  def speed(bus) do
    with {:ok, <<lsb::8>>} <- I2C.write_read(bus, @address, <<@reg_tach_lsb>>, 1),
         {:ok, <<msb::8>>} <- I2C.write_read(bus, @address, <<@reg_tach_msb>>, 1) do
      count = msb <<< 8 ||| lsb
      rpm = if count in [0, 0xFFFF], do: 0, else: round(@tach_constant / count)
      {:ok, rpm}
    end
  end

  @spec set_speed(bus(), 0..100) :: :ok | {:error, term()}
  def set_speed(bus, percentage) when percentage in 0..100 do
    with :ok <- set_prog_bit(bus, true) do
      I2C.write(bus, @address, <<@reg_fan_setting, fan_setting(percentage)>>)
    end
  end

  @spec set_lookup_table(bus(), lookup_table()) :: :ok | {:error, term()}
  def set_lookup_table(bus, table) when length(table) in 1..@lut_max_entries do
    with :ok <- set_prog_bit(bus, true),
         :ok <- write_lut_entries(bus, table) do
      set_prog_bit(bus, false)
    end
  end

  @spec set_forced_external_temp(bus(), -128..127) :: :ok | {:error, term()}
  def set_forced_external_temp(bus, temp) when temp in -128..127 do
    with :ok <- I2C.write(bus, @address, <<@reg_forced_temp, temp::signed-8>>) do
      set_reg_bit(bus, @reg_fan_config, @fan_config_force, true)
    end
  end

  @doc """
  Switch the ALERT/TACH pin to tachometer input mode so the fan speed can be read.
  """
  @spec enable_tachometer(bus()) :: :ok | {:error, term()}
  def enable_tachometer(bus), do: set_reg_bit(bus, @reg_config, @config_alt_tch, true)

  defp write_lut_entries(bus, table) do
    table
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {{temp, percentage}, index}, _acc ->
      temp_reg = @reg_lut_base + index * 2

      with :ok <- I2C.write(bus, @address, <<temp_reg, temp>>),
           :ok <- I2C.write(bus, @address, <<temp_reg + 1, fan_setting(percentage)>>) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp set_prog_bit(bus, enabled?),
    do: set_reg_bit(bus, @reg_fan_config, @fan_config_prog, enabled?)

  defp set_reg_bit(bus, reg, bit, enabled?) do
    with {:ok, <<value::8>>} <- I2C.write_read(bus, @address, <<reg>>, 1) do
      value = if enabled?, do: value ||| bit, else: value &&& bnot(bit)
      I2C.write(bus, @address, <<reg, value>>)
    end
  end

  defp read_external_temp(bus) do
    with {:ok, <<msb::signed-8>>} <- I2C.write_read(bus, @address, <<@reg_external_temp_msb>>, 1),
         {:ok, <<lsb::8>>} <- I2C.write_read(bus, @address, <<@reg_external_temp_lsb>>, 1) do
      {:ok, msb + (lsb >>> 5) * 0.125}
    end
  end

  defp fan_setting(percentage), do: round(percentage / 100 * @fan_setting_max)
end
