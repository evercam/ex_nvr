defmodule ExNVR.Pipelines.Dummy do
  @moduledoc false

  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, _options) do
    spec = [
      child(:source, %ExNVR.Elements.MP4.Depayloader{
        device_id: "5c39b63c-edff-4e4f-be06-f91b2f9efe76",
        start_date: ~U(2023-08-28 10:22:11Z),
        end_date: ~U(2023-08-28 10:22:15Z)
      })
      |> child(:sink, %Membrane.Debug.Sink{
        handle_buffer: &IO.inspect(&1.pts)
      })
    ]

    {[spec: spec], %{}}
  end
end
