defmodule ExNVR.InstallerMode do
  @moduledoc """
  Tracks the "installer mode" flag.

  When enabled, the sign-in page exposes a link to a public installer
  dashboard so an on-site installer can verify device health and adjust
  camera placement without holding admin credentials.

  Storage backends:

    * **Nerves devices** — when `Nerves.Runtime.KV` is loaded the flag is
      written to the KV key returned by `key/0` (`"nvr_installer_mode"`)
      as `"true"`/`"false"`.

    * **Host / Docker / dev** — falls through to a single-line file on
      disk whose path comes from the `:installer_mode_file`
      Application env (configured per-environment in `runtime.exs` /
      `test.exs`). The flag is enabled iff that file exists and its
      trimmed contents equal `"true"`; anything else — missing, empty,
      garbage — is treated as disabled.

  Both backends survive process restarts; the file backend additionally
  survives full host restarts when pointed at a persistent path.
  """

  require Logger

  @key "nvr_installer_mode"

  @spec enabled?() :: boolean()
  def enabled?, do: read() == "true"

  @spec enable() :: :ok | {:error, term()}
  def enable, do: write("true")

  @spec disable() :: :ok | {:error, term()}
  def disable, do: write("false")

  @spec key() :: String.t()
  def key, do: @key

  defp read do
    if kv_available?() do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Nerves.Runtime.KV, :get, [@key])
    else
      read_file()
    end
  end

  defp write(value) do
    if kv_available?() do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Nerves.Runtime.KV, :put, [@key, value])
    else
      write_file(value)
    end
  end

  defp read_file do
    case File.read(file_path()) do
      {:ok, content} -> String.trim(content)
      _missing_or_unreadable -> nil
    end
  end

  defp write_file(value) do
    path = file_path()

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, value) do
      :ok
    else
      {:error, reason} = err ->
        Logger.warning("[InstallerMode] failed to write #{path}: #{inspect(reason)}")
        err
    end
  end

  defp file_path do
    Application.get_env(:ex_nvr, :installer_mode_file) ||
      raise """
      No installer-mode storage configured. Set `config :ex_nvr, \
      :installer_mode_file, "/path/to/state"` (host) or run on a Nerves \
      device with `Nerves.Runtime.KV` available.
      """
  end

  defp kv_available?, do: Code.ensure_loaded?(Nerves.Runtime.KV)
end
