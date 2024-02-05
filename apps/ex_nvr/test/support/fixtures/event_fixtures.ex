defmodule ExNVR.EventsFixture do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Events` context.
  """

  alias ExNVR.Events

  @valid_lpr_event_attributes %{
    plate_number: "01-D-12345",
    direction: "away",
    list_type: "other",
    capture_time: DateTime.utc_now() |> DateTime.to_iso8601(),
    metadata: %{
      confidence: 0.7,
      bounding_box: [0.1, 0.1, 0.15, 0.15],
      vehicle_type: "Bus",
      vehicle_color: "red",
      plate_color: "white"
    }
  }

  @spec valid_lpr_event_attributes(map() | Keyword.t()) :: map()
  def valid_lpr_event_attributes(attrs) do
    Enum.into(attrs, @valid_lpr_event_attributes)
  end

  @spec event_fixture(atom(), ExNVR.Model.Device.t(), map()) :: Events.LPR.t()
  def event_fixture(event_type, device, attrs \\ %{}) do
    do_create_event(event_type, device, attrs)
  end

  defp do_create_event(:lpr, device, attrs) do
    {:ok, event} =
      attrs
      |> valid_lpr_event_attributes()
      |> then(&Events.create_lpr_event(device, &1, nil))

    event
  end

  defp do_create_event(event_type, _device, _attrs) do
    raise("could not create event, no such type #{inspect(event_type)}")
  end
end
