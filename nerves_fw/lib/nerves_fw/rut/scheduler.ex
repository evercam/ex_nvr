defmodule ExNVR.Nerves.RUT.Scheduler do
  @moduledoc false

  defmodule Instance do
    @moduledoc false

    @type t :: %__MODULE__{
            id: String.t(),
            enabled: boolean(),
            start_day: integer(),
            start_time: Time.t(),
            end_day: integer(),
            end_time: Time.t(),
            pin: String.t()
          }

    defstruct [:id, :enabled, :start_day, :start_time, :end_day, :end_time, :pin]

    def from_response(instance) do
      %__MODULE__{
        id: instance["id"],
        enabled: instance["enabled"] == "1",
        start_day: instance["start_day"] && String.to_integer(instance["start_day"]),
        start_time: instance["start_time"] && Time.from_iso8601!(instance["start_time"] <> ":00"),
        end_day: instance["end_day"] && String.to_integer(instance["end_day"]),
        end_time: instance["end_time"] && Time.from_iso8601!(instance["end_time"] <> ":00"),
        pin: instance["pin"]
      }
    end

    def serialize(instance) do
      %{
        id: instance.id,
        enabled: if(instance.enabled, do: "1", else: "0"),
        start_day: "#{instance.start_day}",
        start_time: Calendar.strftime(instance.start_time, "%H:%M"),
        end_day: "#{instance.end_day}",
        end_time: Calendar.strftime(instance.end_time, "%H:%M"),
        pin: instance.pin,
        period: "week"
      }
    end
  end

  @type t :: %__MODULE__{
          enabled: boolean(),
          instances: [Instance.t()]
        }

  defstruct [:enabled, :instances]

  def from_response(scheduler, instances) do
    %__MODULE__{
      enabled: scheduler["enabled"] == "1",
      instances: Enum.map(instances, &Instance.from_response/1)
    }
  end

  def new_instances(schedule, pin, status) do
    schedule
    |> reverse_schedule(status != 1)
    |> Enum.flat_map(fn {day, times} -> new_instance(day, times, pin) end)
    |> combine_instances()
  end

  defdelegate serialize_instance(instance), to: Instance, as: :serialize

  defp reverse_schedule(schedule, false), do: schedule

  defp reverse_schedule(schedule, true) do
    schedule
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new(fn {day, times} -> {day, reverse_times(times)} end)
  end

  defp reverse_times([]), do: [%{start_time: ~T(00:00:00), end_time: ~T(23:59:59)}]

  defp reverse_times(times) do
    start_interval(List.first(times)) ++ between_intervals(times) ++ end_interval(List.last(times))
  end

  defp start_interval(first_interval) do
    case Time.compare(first_interval.start_time, ~T(00:00:00)) do
      :eq -> []
      _other -> [%{start_time: ~T(00:00:00), end_time: Time.add(first_interval.start_time, -1)}]
    end
  end

  defp end_interval(end_interval) do
    case Time.compare(end_interval.end_time, ~T(23:59:59)) do
      :eq -> []
      _other -> [%{start_time: Time.add(end_interval.end_time, 1), end_time: ~T(23:59:59)}]
    end
  end

  defp between_intervals(intervals) do
    Enum.chunk_every(intervals, 2, 1, :discard)
    |> Enum.map(fn [interval1, interval2] ->
      %{start_time: Time.add(interval1.end_time, 1), end_time: Time.add(interval2.start_time, -1)}
    end)
  end

  defp new_instance(day, times, pin) do
    day = rem(String.to_integer(day), 7)

    Enum.map(times, fn %{start_time: start_time, end_time: end_time} ->
      end_time = Time.add(end_time, 1)
      end_day = if Time.compare(end_time, ~T(00:00:00)) == :eq, do: rem(day + 1, 7), else: day

      %Instance{
        enabled: true,
        pin: pin,
        start_day: day,
        start_time: start_time,
        end_day: end_day,
        end_time: end_time
      }
    end)
  end

  defp combine_instances([]), do: []

  defp combine_instances([first_instance | rest]) do
    new_instances =
      rest
      |> Enum.reduce([first_instance], fn instance2, [instance1 | rest] ->
        if instance1.end_day == instance2.start_day and
             Time.compare(instance1.end_time, instance2.start_time) == :eq do
          instance1 = %Instance{
            instance1
            | end_day: instance2.end_day,
              end_time: instance2.end_time
          }

          [instance1 | rest]
        else
          [instance2, instance1 | rest]
        end
      end)
      |> Enum.reverse()

    new_instances
  end
end
