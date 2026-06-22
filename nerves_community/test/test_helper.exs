# The `:qemu` tests boot the ex_nvr firmware in qemu-system-aarch64 and inject
# faults from the outside. They only run where a VM can actually run them:
#
#   * QEMU (and fwup) present  -> build the firmware if it isn't built yet, wire
#     up the env the harness reads (FW_PATH, NERVES_SDK_IMAGES), and INCLUDE the
#     `:qemu` tests.
#   * otherwise                -> SKIP the `:qemu` tests so `mix test` still
#     passes on a machine without QEMU.
#
# Run them with: `mix test.qemu` (an alias for `mix test --no-start --only qemu`
# - `--no-start` keeps the heavy :ex_nvr app from booting on the host, which the
# harness doesn't need and which crashes outside a device).
defmodule QemuEnv do
  @target "qemu_aarch64"

  @spec prepare() :: :include | :exclude
  def prepare do
    if tools_available?() do
      case ensure_firmware() do
        {:ok, fw, images} ->
          System.put_env("FW_PATH", fw)
          System.put_env("NERVES_SDK_IMAGES", images)
          IO.puts("[qemu] firmware: #{fw}")
          IO.puts("[qemu] images:   #{images}")
          :include

        {:error, reason} ->
          skip(reason)
      end
    else
      skip("qemu-system-aarch64 and fwup are required")
    end
  end

  defp skip(reason) do
    IO.puts("[qemu] skipping :qemu tests - #{reason}")
    :exclude
  end

  defp tools_available? do
    System.find_executable("qemu-system-aarch64") != nil and
      System.find_executable("fwup") != nil
  end

  # Use an already-built firmware if present; otherwise build it once (the first
  # build is slow - it compiles the system). Set EXNVR_QEMU_REBUILD=1 to force.
  defp ensure_firmware do
    force = System.get_env("EXNVR_QEMU_REBUILD") in ["1", "true"]

    with false <- force,
         {:ok, fw} <- firmware_path(),
         {:ok, images} <- sdk_images() do
      {:ok, fw, images}
    else
      _ -> build_and_locate()
    end
  end

  defp build_and_locate do
    IO.puts("[qemu] building firmware (MIX_TARGET=#{@target}) - first build is slow…")
    env = [{"MIX_TARGET", @target}]

    with {_, 0} <- System.cmd("mix", ["deps.get"], env: env, stderr_to_stdout: true),
         {_, 0} <- System.cmd("mix", ["firmware"], env: env, stderr_to_stdout: true),
         {:ok, fw} <- firmware_path(),
         {:ok, images} <- sdk_images() do
      {:ok, fw, images}
    else
      {out, status} when is_integer(status) ->
        {:error, "firmware build failed (#{status}):\n#{tail(out)}"}

      :error ->
        {:error, "firmware built but FW_PATH / little_loader.elf not found"}
    end
  end

  defp firmware_path do
    case Path.wildcard("_build/#{@target}_*/nerves/images/*.fw") do
      [fw | _] -> {:ok, fw}
      [] -> :error
    end
  end

  # little_loader.elf lives in the built system artifact's images dir.
  defp sdk_images do
    "#{System.user_home!()}/.nerves/artifacts/ex_nvr_system_qemu_aarch64-*/images"
    |> Path.wildcard()
    |> Enum.find(&File.exists?(Path.join(&1, "little_loader.elf")))
    |> case do
      nil -> :error
      dir -> {:ok, dir}
    end
  end

  defp tail(out), do: String.slice(out, max(String.length(out) - 2_000, 0)..-1//1)
end

case QemuEnv.prepare() do
  :include -> ExUnit.start()
  :exclude -> ExUnit.start(exclude: [:qemu])
end
