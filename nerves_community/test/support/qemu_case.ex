defmodule ExNVR.QemuTest.QemuCase do
  @moduledoc """
  ExUnit case template for the QEMU resilience tests.

  It tags the case `:qemu`, boots a fresh VM for each test, exposes it as `vm`
  in the test context, and destroys it on exit. Pass `VM.boot/1` options with a
  `@tag vm_opts: [...]`, e.g. `@tag vm_opts: [data_disk: %{size: "64M"}]`.

  Run them with `mix test.qemu` (an alias for `mix test --no-start --only qemu`;
  `--no-start` keeps the heavy :ex_nvr app from booting on the host, which the
  harness doesn't need). `test_helper.exs` builds the firmware if needed and
  includes/excludes `:qemu` based on whether QEMU is available.
  """
  use ExUnit.CaseTemplate

  alias ExNVR.QemuTest.VM

  using do
    quote do
      @moduletag :qemu
      @moduletag timeout: 300_000

      alias ExNVR.QemuTest.{Faults, Guest, QMP, VM}
    end
  end

  setup context do
    vm = VM.boot(Map.get(context, :vm_opts, []))
    on_exit(fn -> VM.destroy(vm) end)
    {:ok, vm: vm}
  end
end
