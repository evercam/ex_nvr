defmodule ExNVR.InstallerModeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias ExNVR.InstallerMode

  setup do
    Application.delete_env(:ex_nvr, :installer_mode_fallback)
    on_exit(fn -> Application.delete_env(:ex_nvr, :installer_mode_fallback) end)
    :ok
  end

  test "defaults to disabled" do
    refute InstallerMode.enabled?()
  end

  test "enable/0 flips the flag on" do
    assert :ok = InstallerMode.enable()
    assert InstallerMode.enabled?()
  end

  test "disable/0 flips the flag off again" do
    InstallerMode.enable()
    InstallerMode.disable()
    refute InstallerMode.enabled?()
  end

  test "key/0 returns the KV key" do
    assert InstallerMode.key() == "nvr_installer_mode"
  end
end
