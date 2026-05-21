defmodule ExNVR.InstallerMode do
  @moduledoc """
  Tracks the "installer mode" flag persisted via `Nerves.Runtime.KV`.

  When enabled, the sign-in page exposes a link to a public installer
  dashboard so an on-site installer can verify device health and adjust
  camera placement without holding admin credentials.

  Stored as `"true"`/`"false"` under the KV key returned by `key/0`. On
  systems without `Nerves.Runtime.KV` (host/dev/CI), the flag falls back
  to the `:installer_mode_fallback` Application env key — runtime-only,
  not persisted across restarts.
  """

  @key "nerves_evercam_installer_mode"

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
      Application.get_env(:ex_nvr, :installer_mode_fallback)
    end
  end

  defp write(value) do
    if kv_available?() do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Nerves.Runtime.KV, :put, [@key, value])
    else
      Application.put_env(:ex_nvr, :installer_mode_fallback, value)
    end
  end

  defp kv_available?, do: Code.ensure_loaded?(Nerves.Runtime.KV)
end
