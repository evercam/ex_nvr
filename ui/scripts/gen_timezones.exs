# Regenerates priv/timezones.json (IANA name -> [POSIX TZ string used by ONVIF, country code])
# from the system tzdata, run from the ui folder: elixir scripts/gen_timezones.exs
zoneinfo_dir = "/usr/share/zoneinfo"
dest = Path.join([__DIR__, "..", "priv", "timezones.json"])
# duplicated trees and files that are not timezones
ignore = ~w(posix right posixrules localtime Factory)

if not File.dir?(zoneinfo_dir), do: raise("#{zoneinfo_dir} not found, install tzdata")

countries =
  zoneinfo_dir
  |> Path.join("zone.tab")
  |> File.stream!()
  |> Stream.reject(&String.starts_with?(&1, "#"))
  |> Map.new(fn line ->
    [country, _coordinates, name | _comments] = line |> String.trim() |> String.split("\t")
    {name, country}
  end)

# aliases are symlinks to the canonical zone
resolve_link = fn resolve_link, path ->
  case File.read_link(path) do
    {:ok, target} -> resolve_link.(resolve_link, Path.expand(target, Path.dirname(path)))
    {:error, _reason} -> path
  end
end

country = fn name, path ->
  Map.get_lazy(countries, name, fn ->
    canonical = resolve_link.(resolve_link, path) |> Path.relative_to(zoneinfo_dir)
    countries[canonical]
  end)
end

# a TZif file ends with "\n<posix tz>\n"
timezone = fn path ->
  with <<"TZif", _rest::binary>> = content <- File.read!(path),
       [posix, ""] <- content |> :binary.split("\n", [:global]) |> Enum.take(-2),
       true <- posix != "" and String.printable?(posix) do
    name = Path.relative_to(path, zoneinfo_dir)
    [{name, [posix, country.(name, path)]}]
  else
    _other -> []
  end
end

timezones =
  zoneinfo_dir
  |> Path.join("**")
  |> Path.wildcard()
  |> Enum.reject(fn path ->
    [root | _rest] = path |> Path.relative_to(zoneinfo_dir) |> Path.split()
    root in ignore or File.dir?(path)
  end)
  |> Enum.flat_map(timezone)
  |> Map.new()

File.write!(dest, JSON.encode!(timezones))
IO.puts("Wrote #{dest}")
