defmodule ExNVR.ErrorReporterTest do
  use ExUnit.Case, async: false

  alias ExNVR.ErrorReporter

  defmodule TestReporter do
    @behaviour ExNVR.ErrorReporter

    @impl true
    def report(exception, stacktrace, opts) do
      send(
        Application.fetch_env!(:ex_nvr, :error_reporter_test_pid),
        {:reported, exception, stacktrace, opts}
      )
    end
  end

  defmodule FailingReporter do
    @behaviour ExNVR.ErrorReporter

    @impl true
    def report(_exception, _stacktrace, _opts), do: raise("reporter is down")
  end

  setup do
    Application.put_env(:ex_nvr, :error_reporter_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:ex_nvr, :error_reporters)
      Application.delete_env(:ex_nvr, :error_reporter_test_pid)
    end)
  end

  test "passes the error, group and extra details to every reporter" do
    Application.put_env(:ex_nvr, :error_reporters, [TestReporter])

    error = %RuntimeError{message: "router unreachable"}
    stacktrace = [{__MODULE__, :test, 1, [file: ~c"test.exs", line: 1]}]

    assert :ok =
             ErrorReporter.report(error, stacktrace,
               group: "rut:set_scheduler",
               extra: %{reason: :timeout}
             )

    assert_received {:reported, ^error, ^stacktrace, opts}
    assert opts[:group] == "rut:set_scheduler"
    assert opts[:extra] == %{reason: :timeout}
    assert opts[:report_id] =~ ~r/\A[0-9a-f]{16}\z/
  end

  test "defaults group and extra" do
    Application.put_env(:ex_nvr, :error_reporters, [TestReporter])

    ErrorReporter.report(%RuntimeError{message: "boom"})

    assert_received {:reported, _error, [], opts}
    assert opts[:group] == nil
    assert opts[:extra] == %{}
  end

  test "gives every report its own ID" do
    Application.put_env(:ex_nvr, :error_reporters, [TestReporter])

    ErrorReporter.report(%RuntimeError{message: "boom"})
    ErrorReporter.report(%RuntimeError{message: "boom"})

    assert_received {:reported, _error, _stacktrace, first}
    assert_received {:reported, _error, _stacktrace, second}
    assert first[:report_id] != second[:report_id]
  end

  @tag capture_log: true
  test "a failing reporter does not stop the others or raise" do
    Application.put_env(:ex_nvr, :error_reporters, [FailingReporter, TestReporter])

    assert :ok = ErrorReporter.report(%RuntimeError{message: "boom"})
    assert_received {:reported, _error, _stacktrace, _opts}
  end

  test "works with no reporters configured" do
    assert :ok = ErrorReporter.report(%RuntimeError{message: "boom"})
  end
end
