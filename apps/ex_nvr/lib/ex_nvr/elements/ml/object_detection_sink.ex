defmodule ExNVR.Elements.Ml.ObjectDetectionSink do
  @moduledoc """
  Object Detection Element that processes image buffers and applies machine learning model.
  """

  use Membrane.Sink

  require Membrane.Logger

  alias Membrane.Buffer

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
      pid: opts.pid
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    Membrane.Logger.debug("Setup the ObjectDetection Sink Model and Featurizer")

    state =
      state
      |> load_model()
      |> load_featurizer()

    {[notify_parent: {:pid, self()}], state}
  end

  @impl true
  def handle_write(:input, %Buffer{} = buffer, _ctx, state) do
    image_buffer = buffer.payload
    serving = load_serving(state)
    prediction = predict(serving, image_buffer)

    Membrane.Logger.debug("Object Detection Sink prediction: #{prediction}")

    encoded_img = encode_frame(image_buffer)
    state = Map.merge(state, %{label: prediction, current_encoded_frame: encoded_img})

    send(state.pid, {:detection, prediction, current_encoded_frame: encoded_img})
    {[], state}
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

  defp load_serving(%{model: model, featurizer: featurizer} = _state) do
    Membrane.Logger.debug("Load Model Serving")

    Bumblebee.Vision.image_classification(model, featurizer,
      top_k: 1,
      compile: [batch_size: 1],
      defn_options: [compiler: EXLA]
    )
  end

  defp encode_frame(frame) do
    frame |> Base.encode64()
  end

  defp convert_frame_to_mat(frame) do
    Evision.imdecode(frame, Evision.Constant.cv_IMREAD_ANYCOLOR())
  end

  defp predict(serving, frame) do
    frame_to_mat = convert_frame_to_mat(frame)
    tensor = frame_to_mat |> Evision.Mat.to_nx() |> Nx.backend_transfer()

    %{predictions: [%{label: label}]} = Nx.Serving.run(serving, tensor)

    label
  end
end
