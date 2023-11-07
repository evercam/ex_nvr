defmodule ExNVR.Elements.Ml.ObjectDetectionSink do
  @moduledoc """
  Object Detection Element that processes image buffers and applies machine learning model.
  """

  use Membrane.Sink

  require Membrane.Logger

  alias Membrane.Buffer
  alias Evision, as: Cv

  @min_contour_area 1000
  @max_counter_area 30_000

  def_input_pad :input,
    demand_unit: :buffers,
    flow_control: :auto,
    accepted_format: _any

  def_options pid: [
                spec: pid(),
                description: "Pid of the destination process"
              ]

  @impl true
  def handle_init(_ctx, opts) do
    Membrane.Logger.debug("Init the Object Detection Sink element")

    state = %{
      model: nil,
      featurizer: nil,
      current_encoded_frame: nil,
      serving: nil,
      bg_substractor: nil,
      pid: opts.pid
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    Membrane.Logger.debug("Setup the ObjectDetection Sink Model and Featurizer")

    state =
      state
      # |> load_model()
      # |> load_featurizer()
      # |> load_serving()
      |> load_background_extractor()

    {[notify_parent: {:pid, self()}], state}
  end

  @impl true
  def handle_write(:input, %Buffer{} = buffer, _ctx, state) do
    predictions = detect_motion(
      state,
      convert_frame_to_mat(buffer.payload),
      Membrane.Buffer.get_dts_or_pts(buffer)
    )

    send(state.pid, {:predictions, predictions})
    {[], %{state | predictions: predictions}}
  end

  defp load_model(
         %{model: nil, featurizer: nil, serving: nil} = state,
         model \\ "microsoft/resnet-50"
       ) do
    Membrane.Logger.debug("Load Model <<<#{model}>>>")
    {:ok, model_info} = Bumblebee.load_model({:hf, model})
    %{state | model: model_info}
  end

  defp load_featurizer(
         %{model: _model, featurizer: nil} = state,
         featurizer \\ "microsoft/resnet-50"
       ) do
    Membrane.Logger.debug("Load Model Featurizer <<<#{featurizer}>>>")
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "microsoft/resnet-50"})

    %{state | featurizer: featurizer}
  end

  defp load_serving(%{model: model, featurizer: featurizer} = state) do
    Membrane.Logger.debug("Load Model Serving")

    serving = Bumblebee.Vision.image_classification(model, featurizer,
      top_k: 1,
      compile: [batch_size: 1],
      defn_options: [compiler: EXLA]
    )

    %{state | serving: serving}
  end

  defp load_background_extractor(
    state,
    history \\ 100,
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
    Evision.imdecode(frame, Evision.Constant.cv_IMREAD_ANYCOLOR())
  end

  defp convert_mat_to_tensor(mat) do
    mat |> Evision.Mat.to_nx() |> Nx.backend_transfer()
  end

  defp predict(serving, tensor) do
    %{predictions: [%{label: label}]} = Nx.Serving.run(serving, tensor)

    label
  end

  defp track(serving, frame) do
    contours = find_contours(frame)
    tensor = convert_mat_to_tensor(frame)

    minimal_area = 5000
    maximum_area = 500_000

    contours =
      Enum.reject(contours, fn c ->
        area = Evision.contourArea(c)

        area < minimal_area || area > maximum_area
      end)

    if contours != [] do
      Enum.map(contours, fn c ->
        {x, y, w, h} = dimensions = Evision.boundingRect(c)
        %{label: predict(serving, Nx.slice(tensor, [x, y, 0], [x+w, y+h, 3])), dimensions: dimensions}
      end)
    else
      []
    end
  end

  defp find_contours(frame) do
    myimage_grey =
      Evision.cvtColor(frame, Evision.Constant.cv_COLOR_BGR2GRAY())
      |> Evision.gaussianBlur({23, 23}, 30)

    {_ret, background} =
      Evision.threshold(myimage_grey, 126, 255, Evision.Constant.cv_THRESH_BINARY())

    {contours, _} =
      Evision.findContours(
        background,
        Evision.Constant.cv_RETR_LIST(),
        Evision.Constant.cv_CHAIN_APPROX_NONE()
      )

    contours
  end

  defp detect_motion(%{bg_substractor: bg_substractor}, frame, dts) do
    bg_substractor
    |> Cv.BackgroundSubtractorMOG2.apply(bg_substractor, frame)
    |> Evision.threshold(128, 255, Evision.Constant.cv_THRESH_BINARY())
    |> elem(1)
    |> Evision.findContours(
      Cv.Constant.cv_RETR_EXTERNAL(),
      Cv.Constant.cv_CHAIN_APPROX_SIMPLE()
    )
    |> elem(0)
    |> Enum.reject(fn c ->
      area = Cv.contourArea(c)

      area < @min_contour_area || area > @max_counter_area
    end)
    |> Enum.map(fn contour ->
      dimensions = Cv.boundingRect(contour)
      %{label: "unknown", dimensions: dimensions, dts: dts}
    end)
  end
end
