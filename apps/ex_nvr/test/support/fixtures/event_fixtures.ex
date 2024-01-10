defmodule ExNVR.EventsFixture do
  @valid_lpr_event_attributes %{
    plate_number: "01-D-12345",
    direction: "forward",
    list_type: "visitor",
    confidence: 0.7,
    vehicle_type: "Bus",
    vehicle_color: "red",
    plate_color: "white",
    bounding_box: %{
      x1: "0",
      y1: "100",
      x2: "0",
      y2: "50"
    },
    capture_time:
      ~U"2023-12-12T10:00:00Z"
      |> DateTime.to_iso8601()
      |> String.replace("T", " ")
  }
  alias ExNVR.Events

  def valid_lpr_event_attributes(attrs \\ %{}) do
    Enum.into(attrs, @valid_lpr_event_attributes)
  end

  def lpr_event_fixture(device, attrs \\ %{}) do
    {:ok, event} =
      attrs
      |> valid_lpr_event_attributes()
      |> then(&Events.create_lpr_event(device, &1))

    event
  end
end
