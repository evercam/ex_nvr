defmodule ExNvr.Elements.MotionDetectionSink do

  use Membrane.Sink

  require Membrane.Logger

  alias Membrane.Buffer
  alias Evision, as: Cv
  alias ExNVR.Model.Motion

  def_input_pad :input,
    accepted_format: _any

  def_options device_id: [
    spec: binary(),
    description: "The device id from where to save motion"
  ]

  @min_contour_area 500
  @max_counter_area 30_000

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      bg_substractor: nil,
      device_id: opts.device_id,
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    state =
      state
      |> load_background_extractor()

    {[], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _ctx, state) do
    case detect_motion(state, convert_frame_to_mat(buffer.payload), DateTime.now!("Etc/UTC")) do
      [] -> {[], state}
      predictions ->
        {[notify_parent: {:motions, predictions, state.device_id}], state}
    end
  end

  defp load_background_extractor(
    state,
    history \\ 10,
    var_threshold \\ 25,
    detect_shadow \\ false) do

    extractor = Cv.createBackgroundSubtractorMOG2([
      {"history", history},
      {"varThreshold", var_threshold},
      {"detectShadows", detect_shadow}
    ])

    %{state | bg_substractor: extractor}
  end

  defp convert_frame_to_mat(frame) do
    Cv.imdecode(frame, Cv.Constant.cv_IMREAD_ANYCOLOR())
  end

  defp detect_motion(%{bg_substractor: bg_substractor, device_id: device_id}, frame, time) do
    bg_substractor
    |> Cv.BackgroundSubtractorMOG2.apply(frame)
    |> Evision.threshold(128, 255, Evision.Constant.cv_THRESH_BINARY())
    |> elem(1)
    |> Evision.findContours(
      Cv.Constant.cv_RETR_EXTERNAL(),
      Cv.Constant.cv_CHAIN_APPROX_SIMPLE()
    )
    |> elem(0)
    |> Enum.reject(fn c ->
      area = Cv.contourArea(c)

      area > @max_counter_area || area < @min_contour_area
    end)
    |> Enum.map(fn contour ->
      {x, y, width, height} = Cv.boundingRect(contour)
      %{
        label: "unknown",
        time: time,
        device_id: device_id,
        dimentions: %Motion.MotionLabelDimention{
          x: x,
          y: y,
          width: width,
          height: height
        },
        inserted_at: time,
        updated_at: time,
      }
    end)
  end
end
