defmodule ExNVR.Elements.MotionDetectionBin do
  @moduledoc """
  A bin element that receives an H264 access units and create a snapshot in
  JPEG or PNG format by using the first or last access unit.
  Once the snapshot is created a parent notification is sent: `{:notify_parent, {:snapshot, snapshot}}`
  """

  use Membrane.Bin

  require Membrane.Logger

  alias Membrane.{H264, H265}
  alias ExNVR.Motions

  def_input_pad :input,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      ),
    availability: :always

  def_options device_id: [
                spec: binary(),
                description: "The id of the device where this video belongs"
              ]

  @impl true
  def handle_init(_ctx, opts) do
    spec = [
      bin_input()
      |> child(:decoder, %Membrane.H264.FFmpeg.Decoder{use_shm?: true})
      |> child(:frame_converter, %Membrane.FramerateConverter{framerate: {5, 1}})
      |> child(:jpeg, Turbojpeg.Filter)
      |> child(:sink, %ExNvr.Elements.MotionDetectionSink{device_id: opts.device_id})
    ]

    state = %{
      device_id: opts.device_id,
    }

    {[spec: spec], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[], state}
  end

  @impl true
  def handle_child_notification({:motions, predictions, device_id}, _element, _ctx, state) do
    Phoenix.PubSub.broadcast(
      ExNVR.PubSub,
      "detection-" <> device_id,
      {:motions, predictions}
    )

    Motions.create_all(predictions)
    {[], state}
  end
end
