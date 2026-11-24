defmodule ExNVR.ErrorReporter do
  @moduledoc """
  Report an error the application caught and handled.

  Crashes need nothing from this module: they reach Sentry, and on Nerves also
  NervesHub, through `:logger` handlers. This is for errors that are handled
  and so never crash anything, but that someone should still hear about.

  The error always goes to Sentry, then to each module listed under
  `:error_reporters`:

      config :ex_nvr, error_reporters: [ExNVR.Nerves.ErrorReporting.NervesHubReporter]

  Every report gets a random `report_id`, sent to Sentry as a tag and to each
  reporter, so the same error can be found in every system it went to.
  Sentry's own event ID can't be used for this: Sentry sends in the
  background and returns before an event ID exists.

  ## Options

    * `:group` - a key of your own to group these reports under, instead of
      grouping by stacktrace. Used as the Sentry fingerprint and passed on to
      the other reporters, so both systems group the error the same way.
    * `:extra` - a map of details about this one report.
  """

  require Logger

  @doc """
  Called once per report with the exception, its stacktrace and these options:

    * `:group` - the `:group` passed to `report/3`, or `nil`.
    * `:extra` - the `:extra` map passed to `report/3`, or `%{}`.
    * `:report_id` - the ID this report was tagged with in Sentry.
  """
  @callback report(Exception.t(), Exception.stacktrace(), keyword()) :: any()

  @spec report(Exception.t(), Exception.stacktrace(), keyword()) :: :ok
  def report(exception, stacktrace \\ [], opts \\ []) do
    group = Keyword.get(opts, :group)
    extra = Keyword.get(opts, :extra, %{})

    report_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    report_to_sentry(exception, stacktrace, group, extra, report_id)

    reporter_opts = [group: group, extra: extra, report_id: report_id]

    for reporter <- Application.get_env(:ex_nvr, :error_reporters, []) do
      call_reporter(reporter, exception, stacktrace, reporter_opts)
    end

    :ok
  end

  defp report_to_sentry(exception, stacktrace, group, extra, report_id) do
    opts = [stacktrace: stacktrace, extra: extra, tags: %{"report_id" => report_id}]
    opts = if group, do: Keyword.put(opts, :fingerprint, [to_string(group)]), else: opts

    _result = Sentry.capture_exception(exception, opts)
    :ok
  end

  # The caller is already dealing with one error, so a reporter that fails must
  # not hand it a second one.
  defp call_reporter(reporter, exception, stacktrace, opts) do
    reporter.report(exception, stacktrace, opts)
  rescue
    error ->
      Logger.warning(
        "[ErrorReporter] #{inspect(reporter)} failed to report an error: #{Exception.message(error)}"
      )
  end
end
