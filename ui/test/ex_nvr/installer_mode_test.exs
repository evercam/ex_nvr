defmodule ExNVR.InstallerModeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias ExNVR.InstallerMode

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "installer_mode_test_#{System.unique_integer([:positive])}"
      )

    previous = Application.get_env(:ex_nvr, :installer_mode_file)
    Application.put_env(:ex_nvr, :installer_mode_file, path)

    on_exit(fn ->
      File.rm(path)
      if previous, do: Application.put_env(:ex_nvr, :installer_mode_file, previous)
    end)

    %{path: path}
  end

  test "defaults to disabled when the state file is missing" do
    refute InstallerMode.enabled?()
  end

  test "enable/0 writes the file and flips the flag on", %{path: path} do
    assert :ok = InstallerMode.enable()
    assert InstallerMode.enabled?()
    assert File.read!(path) == "true"
  end

  test "disable/0 flips the flag off again", %{path: path} do
    InstallerMode.enable()
    InstallerMode.disable()
    refute InstallerMode.enabled?()
    assert File.read!(path) == "false"
  end

  test "ignores garbage file contents", %{path: path} do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "yes please")
    refute InstallerMode.enabled?()
  end

  test "trims surrounding whitespace before matching", %{path: path} do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "  true\n")
    assert InstallerMode.enabled?()
  end

  test "key/0 returns the KV key" do
    assert InstallerMode.key() == "nvr_installer_mode"
  end
end
