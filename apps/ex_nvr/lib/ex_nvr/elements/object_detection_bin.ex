defmodule ExNVR.Elements.ObjectDetectionBin do
  @moduledoc """
  A bin element that receives an H264 access units and create a snapshot in
  JPEG or PNG format by using the first or last access unit.
  Once the snapshot is created a parent notification is sent: `{:notify_parent, {:snapshot, snapshot}}`
  """

  use Membrane.Bin

  require Membrane.Logger

  alias Membrane.H264

  def_input_pad :input,
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :on_request,
    options: [
      format: [
        spec: :jpeg,
        default: :jpeg
      ],
      rank: [
        spec: :first | :last,
        default: :last,
        description: """
        Create a snapshot from the first or last access unit
        """
      ]
    ]

  @impl true
  def handle_init(_ctx, _options) do
    Membrane.Logger.error("In detector")
    {[], %{}}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[notify_parent: {:pid, self()}], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, ref) = pad, _ctx, state) do
    IO.inspect("handle_pad_added ObjectDetection element")

    spec = [
      bin_input(pad)
      |> child({:decoder, ref}, %Membrane.H264.FFmpeg.Decoder{use_shm?: true})
      |> child(:frame_converter, %Membrane.FramerateConverter{framerate: {1, 1}})
      |> child({:jpeg, ref}, Turbojpeg.Filter)
      |> child({:vision_sink, ref}, %ExNVR.Elements.Ml.ObjectDetectionSink{pid: self()})
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_element_end_of_stream({:vision_sink, ref}, _pad, ctx, state) do
    Map.keys(ctx.children)
    |> Enum.filter(fn
      {_, ^ref} -> true
      _ -> false
    end)
    |> then(&{[remove_child: &1], state})
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:predictions, predictions}, _ctx, state) do
    Membrane.Logger.debug("Predictions from Object Detection Sink: #{predictions}")

    {[notify_parent: {:detection, predictions}], state}
  end
end
