defmodule ExNVR.Model.Device.SnapshotConfig do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @days_of_week ~w(1 2 3 4 5 6 7)

  @type t :: %__MODULE__{
          enabled: boolean(),
          upload_interval: integer(),
          remote_storage: binary(),
          schedule: list()
        }

  @primary_key false
  embedded_schema do
    field :enabled, :boolean
    field :upload_interval, :integer, default: 30
    field :remote_storage, :string
    field :schedule, :map
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    changeset =
      struct
      |> cast(params, [:enabled, :upload_interval, :remote_storage, :schedule])

    enabled = get_field(changeset, :enabled)
    validate_config(changeset, enabled)
  end

  defp validate_config(changeset, true) do
    changeset
    |> validate_required([:enabled, :upload_interval, :remote_storage, :schedule])
    |> validate_number(:upload_interval,
      greater_than_or_equal_to: 5,
      less_than_or_equal_to: 3600
    )
    |> validate_schedule()
  end

  defp validate_config(changeset, _enabled) do
    changeset
    |> put_change(:upload_interval, 0)
    |> put_change(:remote_storage, nil)
    |> put_change(:schedule, %{})
  end

  defp validate_schedule(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_schedule(changeset) do
    changeset
    |> get_field(:schedule)
    |> do_validate_schedule()
    |> case do
      {:ok, schedule} ->
        put_change(changeset, :schedule, schedule)

      {:error, :invalid_schedule_days} ->
        add_error(changeset, :schedule, "Invalid schedule days")

      {:error, :invalid_time_intervals} ->
        add_error(changeset, :schedule, "Invalid schedule time intervals format")

      {:error, :invalid_time_interval_range} ->
        add_error(
          changeset,
          :schedule,
          "Invalid schedule time intervals range (start time must be before end time)"
        )

      {:error, :overlapping_intervals} ->
        add_error(changeset, :schedule, "Schedule time intervals must not overlap")
    end
  end

  defp do_validate_schedule(schedule) do
    schedule =
      schedule
      |> Enum.into(%{
        "1" => [],
        "2" => [],
        "3" => [],
        "4" => [],
        "5" => [],
        "6" => [],
        "7" => []
      })

    with {:ok, schedule} <- validate_schedule_days(schedule),
         {:ok, parsed_schedule} <- parse_schedule(schedule),
         {:ok, _parsed_schedule} <- validate_schedule_intervals(parsed_schedule) do
      schedule
      |> Enum.map(fn {day, intervals} -> {day, Enum.sort(intervals)} end)
      |> Map.new()
      |> then(&{:ok, &1})
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

  def parse_schedule(schedule) do
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
end
