defmodule ExNVR.Model.Schedule do
  @moduledoc false

  @days_of_week ~w(1 2 3 4 5 6 7)

  @spec validate(map()) :: {:ok, map()} | {:error, atom()}
  def validate(schedule) do
    schedule =
      Enum.into(schedule, %{
        "1" => [],
        "2" => [],
        "3" => [],
        "4" => [],
        "5" => [],
        "6" => [],
        "7" => []
      })

    with {:ok, schedule} <- validate_schedule_days(schedule),
         {:ok, parsed_schedule} <- parse(schedule),
         {:ok, _parsed_schedule} <- validate_schedule_intervals(parsed_schedule) do
      schedule
      |> Enum.map(fn {day, intervals} -> {day, Enum.sort(intervals)} end)
      |> Map.new()
      |> then(&{:ok, &1})
    end
  end

  @spec parse(map()) :: {:ok, map()} | {:error, atom()}
  def parse(schedule) do
    schedule
    |> Enum.reduce_while({:ok, %{}}, fn {day_of_week, time_intervals}, {:ok, acc} ->
      case parse_day_schedule(time_intervals) do
        :invalid_time_intervals ->
          {:halt, {:error, :invalid_time_intervals}}

        parsed_time_intervals ->
          {:cont, {:ok, Map.put(acc, day_of_week, parsed_time_intervals)}}
      end
    end)
  end

  @spec parse!(map()) :: map()
  def parse!(schedule) do
    case parse(schedule) do
      {:ok, schedule} ->
        schedule

      {:error, reason} ->
        raise "failed to parse schedule: #{inspect(schedule)}, reason: #{inspect(reason)}"
    end
  end

  @spec scheduled?(map(), DateTime.t()) :: boolean()
  def scheduled?(schedule, datetime) do
    day_of_week = DateTime.to_date(datetime) |> Date.day_of_week()
    time = DateTime.to_time(datetime) |> Time.truncate(:second)

    case Map.get(schedule, to_string(day_of_week)) do
      nil -> false
      time_intervals -> Enum.any?(time_intervals, &time_in_range?(time, &1))
    end
  end

  defp validate_schedule_days(schedule) do
    schedule
    |> Map.keys()
    |> Enum.all?(&Enum.member?(@days_of_week, &1))
    |> case do
      true -> {:ok, schedule}
      false -> {:error, :invalid_schedule_days}
    end
  end

  defp parse_day_schedule(time_intervals) when is_list(time_intervals) do
    Enum.reduce_while(time_intervals, [], fn time_interval, acc ->
      with [start_time, end_time] <- String.split(time_interval, "-", parts: 2),
           {:ok, start_time} <- Time.from_iso8601(start_time <> ":00"),
           {:ok, end_time} <- Time.from_iso8601(end_time <> ":59") do
        {:cont, acc ++ [%{start_time: start_time, end_time: end_time}]}
      else
        _error -> {:halt, :invalid_time_intervals}
      end
    end)
  end

  defp parse_day_schedule(_time_intervals), do: :invalid_time_intervals

  defp validate_schedule_intervals(schedule) do
    Enum.reduce_while(schedule, :ok, fn {_day_of_week, time_intervals}, _acc ->
      sorted_intervals =
        Enum.sort(time_intervals, &(Time.compare(&1.start_time, &2.start_time) == :lt))

      with true <- Enum.all?(sorted_intervals, &valid_time_interval?/1),
           :ok <- no_overlapping_intervals(sorted_intervals) do
        {:cont, :ok}
      else
        false -> {:halt, :invalid_time_interval_range}
        :overlapping_intervals -> {:halt, :overlapping_intervals}
      end
    end)
    |> case do
      :ok -> {:ok, schedule}
      error -> {:error, error}
    end
  end

  defp valid_time_interval?(%{start_time: start_time, end_time: end_time}) do
    Time.compare(end_time, start_time) == :gt
  end

  defp no_overlapping_intervals(intervals) do
    intervals
    |> Enum.reduce_while(nil, &check_overlap/2)
    |> case do
      :overlapping_intervals ->
        :overlapping_intervals

      _end_time ->
        :ok
    end
  end

  defp check_overlap(%{start_time: start_time, end_time: end_time}, prev_end_time) do
    cond do
      is_nil(prev_end_time) -> {:cont, end_time}
      Time.compare(start_time, prev_end_time) in [:gt, :eq] -> {:cont, end_time}
      true -> {:halt, :overlapping_intervals}
    end
  end

  defp time_in_range?(time, %{start_time: start_time, end_time: end_time}) do
    Time.compare(time, start_time) in [:gt, :eq] and Time.compare(time, end_time) in [:lt, :eq]
  end
end
