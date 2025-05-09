defmodule ExNVR.Mix.Utils do
  def plugin_paths do
    System.get_env("PLUGIN_PATHS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&Path.expand(&1, Path.dirname(__ENV__.file)))
  end

  def watch_patterns do
    [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/ex_nvr_web/(controllers|live|components)/.*(ex|heex)$"
    ] ++ plugin_watch_patterns()
  end

  def watch_dirs do
    ["." | plugin_paths()]
  end

  defp plugin_watch_patterns do
    plugin_paths()
    |> Enum.flat_map(fn path ->
      escaped = Regex.escape(path)

      [
        ~r"#{escaped}/(controllers|live|components)/.*(ex|heex)$",
        ~r"#{escaped}/assets/.*(js|css|png|jpeg|jpg|gif|svg)$",
        ~r"#{escaped}/assets/js/.*(js|css|png|jpeg|jpg|gif|svg)$"
      ]
    end)
  end
end
