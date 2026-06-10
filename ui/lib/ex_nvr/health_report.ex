defmodule ExNVR.HealthReport do
  @moduledoc """
  Evaluates a set of named "good-health" checks and returns an aggregate
  report for the dashboard.

  Each check is a plain map with a `:kind` discriminator plus kind-specific
  fields. A check resolves to one of:

    * `:ok` — every condition is satisfied
    * `:failing` — a condition is broken (value out of range, missing data,
      etc.) and the report describes which one
    * `:insufficient_data` — we can't tell yet (no samples in window, state
      not collected yet)

  The list of checks is read from `Application.get_env(:ex_nvr,
  :health_checks, [])` — each firmware/environment declares the checks
  it wants in its own `config.exs`; with no config the report returns
  `[]` and the dashboard hides the panel. Pass `:checks` explicitly to
  override (used by tests).

  ## Kinds

    * `:devices_recording` — every configured device is in `:recording`
      state and there is at least one device.
    * `:state_field_present` — the named key under `SystemStatus.get_all/0`
      is non-nil. `field: :ups`, etc.
    * `:state_field` — the value at `field`/`path` (path optional, walks
      `Map.get/2` for nested string-keyed maps from set/3 payloads) equals
      `expected` (scalar) or is in `expected` (list).
    * `:mobius_range` — `Mobius.Exports.series/4` for `metric` (with
      optional `tags`) over `window` has every sample inside `range`
      (`min..max`). Empty / under-covered window → `:insufficient_data`.

  ## Injecting data sources

  Both data sources and the check list can be injected via opts, which is
  how the unit tests avoid touching `Application` env and external
  services:

      ExNVR.HealthReport.report(
        checks: [%{name: :foo, label: "...", kind: :devices_recording}],
        devices: [%Device{state: :recording, name: "Cam"}]
      )

  Supported opts:

    * `:checks` — list of check maps (default: `checks/0`)
    * `:devices` — list of device structs/maps with `:state` and `:name`
      (default: `ExNVR.Devices.list/0`)
    * `:state` — map mirroring `SystemStatus.get_all/0`
      (default: `SystemStatus.get_all/0`)
    * `:series_fn` — `(metric, tags, window) -> [%{value: number}]`
      (default: `Mobius.Exports.series(metric, :last_value, tags, last: window)`)
  """

  alias ExNVR.{Devices, SystemStatus}

  @type status :: :ok | :failing | :insufficient_data
  @type check :: map()
  @type result :: %{
          name: atom(),
          label: String.t(),
          status: status(),
          detail: String.t() | nil
        }

  @doc """
  Run every configured check and return a list of results in declaration
  order. See module docs for the opts.
  """
  @spec report(keyword()) :: [result()]
  def report(opts \\ []) do
    checks = Keyword.get(opts, :checks, checks())
    ctx = build_context(opts)
    Enum.map(checks, &evaluate(&1, ctx))
  end

  @doc """
  Aggregate status across all checks: `:failing` if any check is failing,
  `:insufficient_data` if any is unknown, otherwise `:ok`. An empty list
  returns `:ok` (nothing to fail).
  """
  @spec overall([result()]) :: status()
  def overall(results) do
    cond do
      Enum.any?(results, &(&1.status == :failing)) -> :failing
      Enum.any?(results, &(&1.status == :insufficient_data)) -> :insufficient_data
      true -> :ok
    end
  end

  @doc """
  Checks declared in `Application.get_env(:ex_nvr, :health_checks, [])`.
  Returns `[]` when no firmware/environment has configured any.
  """
  @spec checks() :: [check()]
  def checks, do: Application.get_env(:ex_nvr, :health_checks, [])

  ## Context — explicit injections, no eager defaults so tests can ignore
  ## the sources irrelevant to the kinds they exercise.

  defp build_context(opts) do
    %{
      devices: Keyword.get(opts, :devices),
      state: Keyword.get(opts, :state),
      series_fn: Keyword.get(opts, :series_fn)
    }
  end

  defp default_series(metric, tags, window) do
    Mobius.Exports.series(metric, :last_value, tags, last: window)
  end

  ## Evaluation

  defp evaluate(%{kind: :devices_recording} = check, ctx) do
    devices = ctx.devices || safe(&Devices.list/0, [])

    cond do
      devices == [] ->
        result(check, :failing, "No cameras configured")

      Enum.all?(devices, &(&1.state == :recording)) ->
        result(check, :ok, "#{length(devices)} camera#{plural(devices)} recording")

      true ->
        not_recording = Enum.reject(devices, &(&1.state == :recording))
        names = Enum.map_join(not_recording, ", ", & &1.name)
        result(check, :failing, "#{length(not_recording)} not recording: #{names}")
    end
  end

  defp evaluate(%{kind: :state_field_present, field: field} = check, ctx) do
    state = ctx.state || safe(&SystemStatus.get_all/0, %{})

    case Map.get(state, field) do
      nil -> result(check, :insufficient_data, "No data for #{field}")
      _present -> result(check, :ok, nil)
    end
  end

  defp evaluate(
         %{kind: :state_field, field: field, expected: expected} = check,
         ctx
       ) do
    state = ctx.state || safe(&SystemStatus.get_all/0, %{})
    path = Map.get(check, :path, [])
    actual = state |> Map.get(field) |> dig(path)

    cond do
      is_nil(actual) ->
        result(check, :insufficient_data, "No data for #{field_label(field, path)}")

      matches?(actual, expected) ->
        result(check, :ok, "#{field_label(field, path)} = #{inspect(actual)}")

      true ->
        result(
          check,
          :failing,
          "#{field_label(field, path)} = #{inspect(actual)}, want #{inspect(expected)}"
        )
    end
  end

  defp evaluate(
         %{kind: :mobius_range, metric: metric, range: lo..hi//_} = check,
         ctx
       ) do
    series_fn = ctx.series_fn || (&default_series/3)
    tags = Map.get(check, :tags, %{})
    window = Map.get(check, :window, {5, :minute})

    samples = safe(fn -> series_fn.(metric, tags, window) end, [])
    values = Enum.map(samples, &sample_value/1) |> Enum.reject(&is_nil/1)
    out_of_range = Enum.find(values, fn v -> v < lo or v > hi end)

    cond do
      values == [] ->
        result(check, :insufficient_data, "No samples for #{metric}")

      out_of_range != nil ->
        result(check, :failing, "#{metric} = #{out_of_range} (want #{lo}..#{hi})")

      true ->
        result(check, :ok, "#{length(values)} samples in #{lo}..#{hi}")
    end
  end

  defp evaluate(%{kind: kind} = check, _ctx),
    do: result(check, :insufficient_data, "Unknown check kind #{inspect(kind)}")

  defp sample_value(n) when is_number(n), do: n
  defp sample_value(%{value: v}) when is_number(v), do: v
  defp sample_value(_), do: nil

  ## Helpers

  defp result(%{name: name, label: label}, status, detail) do
    %{name: name, label: label, status: status, detail: detail}
  end

  defp dig(value, []), do: value
  defp dig(map, [key | rest]) when is_map(map), do: dig(Map.get(map, key), rest)
  defp dig(_other, _path), do: nil

  defp matches?(actual, expected) when is_list(expected), do: actual in expected
  defp matches?(actual, expected), do: actual == expected

  defp field_label(field, []), do: to_string(field)
  defp field_label(field, path), do: Enum.join([field | path], ".")

  defp plural([_]), do: ""
  defp plural(_), do: "s"

  defp safe(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end
end
