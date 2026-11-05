defmodule ExNVR.Devices.Cameras.HttpClient.Milesight.Timezone do
  @moduledoc false

  # Map IANA timezones to the timezones supported by Milesight cameras.
  # Milesight timezones are "<UTC offset in POSIX format> <zone code>", the camera applies the DST
  # rules of the zone code, so each one is described by a representative IANA timezone and we pick
  # one with the same offset and DST rules.

  alias ExNVR.Devices.Cameras.Timezones

  # from the camera web UI (zoneOptions), outdated zones are excluded below by the offset check
  @zones [
    {"UTC11 Samoa", "Pacific/Pago_Pago"},
    {"UTC10 Cook", "Pacific/Rarotonga"},
    {"UTC10 Polynesia", "Pacific/Tahiti"},
    {"UTC10 USA", "Pacific/Honolulu"},
    {"UTC10 USA2", "America/Adak"},
    {"UTC9 USA", "America/Anchorage"},
    {"UTC8 CAN", "America/Vancouver"},
    {"UTC8 MEX", "America/Tijuana"},
    {"UTC8 USA", "America/Los_Angeles"},
    {"UTC7 CAN", "America/Edmonton"},
    {"UTC7 MEX", "America/Mazatlan"},
    {"UTC7 USA", "America/Denver"},
    {"UTC6 CAN", "America/Winnipeg"},
    {"UTC6 CHL", "Pacific/Easter"},
    {"UTC6 MEX", "America/Mexico_City"},
    {"UTC6 USA", "America/Chicago"},
    {"UTC5 BHS", "America/Nassau"},
    {"UTC5 BRA", "America/Rio_Branco"},
    {"UTC5 CAN", "America/Toronto"},
    {"UTC5 CUB", "America/Havana"},
    {"UTC5 USA", "America/New_York"},
    {"UTC4 VEN", "America/Caracas"},
    {"UTC4 CAN", "America/Halifax"},
    {"UTC4 CHL", "America/Santiago"},
    {"UTC4 PRY", "America/Asuncion"},
    {"UTC4 TTB", "America/Port_of_Spain"},
    {"UTC4 BMU", "Atlantic/Bermuda"},
    {"UTC4 FLK", "Atlantic/Stanley"},
    {"UTC3:30 CAN", "America/St_Johns"},
    {"UTC3 ARG", "America/Argentina/Buenos_Aires"},
    {"UTC3 BRA2", "America/Sao_Paulo"},
    {"UTC3 GRL", "America/Nuuk"},
    {"UTC2 BRA", "America/Noronha"},
    {"UTC1 PRT", "Atlantic/Azores"},
    {"UTC0 FRO", "Atlantic/Faroe"},
    {"UTC0 IRL", "Europe/Dublin"},
    {"UTC0 PRT", "Europe/Lisbon"},
    {"UTC0 ESP", "Atlantic/Canary"},
    {"UTC0 GBR", "Europe/London"},
    {"UTC-1 ALB", "Europe/Tirane"},
    {"UTC-1 AUT", "Europe/Vienna"},
    {"UTC-1 BEL", "Europe/Brussels"},
    {"UTC-1 HRV", "Europe/Zagreb"},
    {"UTC-1 CZE", "Europe/Prague"},
    {"UTC-1 DNK", "Europe/Copenhagen"},
    {"UTC-1 FRA", "Europe/Paris"},
    {"UTC-1 GER", "Europe/Berlin"},
    {"UTC-1 HUN", "Europe/Budapest"},
    {"UTC-1 ITA", "Europe/Rome"},
    {"UTC-1 LUX", "Europe/Luxembourg"},
    {"UTC-1 MAK", "Europe/Skopje"},
    {"UTC-1 NAM", "Africa/Windhoek"},
    {"UTC-1 NLD", "Europe/Amsterdam"},
    {"UTC-1 NGR", "Africa/Lagos"},
    {"UTC-1 NOR", "Europe/Oslo"},
    {"UTC-1 POL", "Europe/Warsaw"},
    {"UTC-1 YUG", "Europe/Belgrade"},
    {"UTC-1 SVK", "Europe/Bratislava"},
    {"UTC-1 SVN", "Europe/Ljubljana"},
    {"UTC-1 ESP", "Europe/Madrid"},
    {"UTC-1 SWE", "Europe/Stockholm"},
    {"UTC-1 CHE", "Europe/Zurich"},
    {"UTC-1 GIB", "Europe/Gibraltar"},
    {"UTC-2 BGR", "Europe/Sofia"},
    {"UTC-2 CYP", "Asia/Nicosia"},
    {"UTC-2 CAT", "Africa/Maputo"},
    {"UTC-2 EGY", "Africa/Cairo"},
    {"UTC-2 EST", "Europe/Tallinn"},
    {"UTC-2 FIN", "Europe/Helsinki"},
    {"UTC-2 GAZ", "Asia/Gaza"},
    {"UTC-2 GRC", "Europe/Athens"},
    {"UTC-2 ISR", "Asia/Jerusalem"},
    {"UTC-2 LVA", "Europe/Riga"},
    {"UTC-2 LBN", "Asia/Beirut"},
    {"UTC-2 MDA", "Europe/Chisinau"},
    {"UTC-2 PAL", "Asia/Hebron"},
    {"UTC-2 ROU", "Europe/Bucharest"},
    {"UTC-2 RUS", "Europe/Kaliningrad"},
    {"UTC-2 SAC", "Africa/Johannesburg"},
    {"UTC-2 SYR", "Asia/Damascus"},
    {"UTC-2 UKR", "Europe/Kyiv"},
    {"UTC-3 JOR", "Asia/Amman"},
    {"UTC-3 BLR", "Europe/Minsk"},
    {"UTC-3 EAT", "Africa/Nairobi"},
    {"UTC-3 IRQ", "Asia/Baghdad"},
    {"UTC-3 AST", "Asia/Kuwait"},
    {"UTC-3 QTR", "Asia/Qatar"},
    {"UTC-3 RUS", "Europe/Moscow"},
    {"UTC-3 KSA", "Asia/Riyadh"},
    {"UTC-3 TUR", "Europe/Istanbul"},
    {"UTC-3:30 IRN", "Asia/Tehran"},
    {"UTC-4 ARM", "Asia/Yerevan"},
    {"UTC-4 AZE", "Asia/Baku"},
    {"UTC-4 GEO", "Asia/Tbilisi"},
    {"UTC-4 RUS", "Europe/Samara"},
    {"UTC-4 UAE", "Asia/Dubai"},
    {"UTC-5 KAZ1", "Asia/Aqtau"},
    {"UTC-5 KAZ", "Asia/Aqtobe"},
    {"UTC-5 PAK", "Asia/Karachi"},
    {"UTC-5 RUS", "Asia/Yekaterinburg"},
    {"UTC-5:30 IND", "Asia/Kolkata"},
    {"UTC-5:45 NPL", "Asia/Kathmandu"},
    {"UTC-6 KAZ", "Asia/Almaty"},
    {"UTC-6 KGZ", "Asia/Bishkek"},
    {"UTC-6 RUS", "Asia/Omsk"},
    {"UTC-6:30 MMT", "Asia/Yangon"},
    {"UTC-7 RUS", "Asia/Krasnoyarsk"},
    {"UTC-7 THA", "Asia/Bangkok"},
    {"UTC-7 VTN", "Asia/Ho_Chi_Minh"},
    {"UTC-8 AUS", "Australia/Perth"},
    {"UTC-8 CHN", "Asia/Shanghai"},
    {"UTC-8 SGP", "Asia/Singapore"},
    {"UTC-9 JPN", "Asia/Tokyo"},
    {"UTC-9 KOR", "Asia/Seoul"},
    {"UTC-9:30 AUS", "Australia/Adelaide"},
    {"UTC-9:30 AUS2", "Australia/Darwin"},
    {"UTC-10 AUS", "Australia/Sydney"},
    {"UTC-10 AUS2", "Australia/Brisbane"},
    {"UTC-10 AUS3", "Australia/Hobart"},
    {"UTC-10 RUS", "Asia/Vladivostok"},
    {"UTC-10:30 AUS", "Australia/Lord_Howe"},
    {"UTC-11 NCL", "Pacific/Noumea"},
    {"UTC-12 NZL", "Pacific/Auckland"},
    {"UTC-12 RUS", "Asia/Kamchatka"},
    {"UTC-12:45 NZL", "Pacific/Chatham"},
    {"UTC-13 TON", "Pacific/Tongatapu"}
  ]

  @doc """
  Get the Milesight timezone (timeZoneTz, zoneNameTz) and whether to enable DST for an IANA timezone.
  """
  @spec find(String.t()) :: {:ok, {String.t(), String.t(), boolean()}} | :error
  def find(timezone) do
    with {:ok, posix} <- Timezones.posix(timezone),
         {offset, dst} <- parse_posix(posix),
         [{zone, _rules, _country} | _rest] <-
           candidates(offset, dst, Timezones.country(timezone)) do
      [tz, name] = String.split(zone, " ")
      {:ok, {tz, name, dst != nil}}
    else
      _other -> :error
    end
  end

  # without DST any zone with the same offset works since DST is disabled on the camera,
  # prefer zones of the same country then the ones without DST
  defp candidates(offset, nil, country) do
    supported_zones()
    |> Enum.filter(fn {_zone, {zone_offset, _dst}, _country} -> zone_offset == offset end)
    |> Enum.sort_by(fn {_zone, {_offset, dst}, zone_country} ->
      {zone_country != country, dst != nil}
    end)
  end

  defp candidates(offset, dst, country) do
    supported_zones()
    |> Enum.filter(fn {_zone, rules, _country} -> rules == {offset, dst} end)
    |> Enum.sort_by(fn {_zone, _rules, zone_country} -> zone_country != country end)
  end

  defp supported_zones do
    for {zone, timezone} <- @zones,
        {:ok, posix} = Timezones.posix(timezone),
        {offset, _dst} = rules = parse_posix(posix),
        offset == zone |> String.split(" ") |> hd() |> String.trim_leading("UTC"),
        do: {zone, rules, Timezones.country(timezone)}
  end

  @posix_regex ~r/^(?:<[^>]+>|[A-Za-z]+)(?<offset>[+-]?\d+(?::\d+)*)((?<dst>(?:<[^>]+>|[A-Za-z]+))(?<dst_offset>[+-]?\d+(?::\d+)*)?(?<rules>,.*)?)?$/

  # "CST6CDT,M3.2.0,M11.1.0" => {"6", {"", ",M3.2.0,M11.1.0"}}, abbreviations are ignored
  defp parse_posix(posix) do
    case Regex.named_captures(@posix_regex, posix) do
      %{"offset" => offset, "dst" => ""} ->
        {String.trim_leading(offset, "+"), nil}

      %{"offset" => offset} = captures ->
        {String.trim_leading(offset, "+"), {captures["dst_offset"], captures["rules"]}}

      nil ->
        nil
    end
  end
end
