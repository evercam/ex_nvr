defmodule ExNVR.Pipelines.ObjectDetection do
  @moduledoc """
  Pipeline responsible for performin object detection.
  """

  use Membrane.Pipeline

  require Membrane.Logger

  def start_link(options) do
    Pipeline.start_link(__MODULE__, Keyword.put(options, :caller, self()))
  end

  @impl true
  def handle_init(_ctx, _options) do
    Membrane.Logger.info("Start Object Detection pipeline")

    state = %{
      model: nil,
      featurizer: nil,
      label: nil,
      current_encoded_frame: nil
    }

    spec =
      [
        child(:source, Membrane.CameraCapture)
        |> child(:converter, %Membrane.FFmpeg.SWScale.PixelFormatConverter{format: :I420})
        |> child(:scaler, %Membrane.FFmpeg.SWScale.Scaler{output_width: 224, output_height: 224})
        # |> child(framerate_converter: %Membrane.FramerateConverter{framerate: {2, 1}})
        |> child(:jpeg, Turbojpeg.Filter)
        |> child(:sink, %ExNVR.Elements.Process.Sink{pid: self()})
      ]

    {[spec: spec], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    Membrane.Logger.debug("Setup the ObjectDetection element, start loading the Model")

    state =
      state
      |> load_model()
      |> load_featurizer()

    {[], state}
  end

  # @impl true
  # def handle_child_notification({:detection, prediction}, _element, _ctx, state) do
  #   current_encoded_frame = state.current_encoded_frame
  #   IO.inspect("current_encoded_frame")
  #   IO.inspect(current_encoded_frame)
  #   Phoenix.PubSub.broadcast(ExNVR.PubSub, "detection", {:prediction, prediction, current_encoded_frame})
  #   {:ok, state}
  # end

  @impl true
  def handle_child_notification(notification, _element, _ctx, state) do
    IO.inspect("Got NOTIFICATION: #{notification}")
    {[], state}
  end

  @impl true
  def handle_info({:buffer, image}, _ctx, state) do
    # IO.inspect("Handling INFOOOOO")
    serving = load_serving(state)
    prediction = predict(serving, image)
    IO.inspect("prediction:============== #{prediction}==================")
    encoded_img = encode_frame(image)
    # {[notify_parent: {:detection, prediction}], %{state | current_encoded_frame: encoded_img}}
    Phoenix.PubSub.broadcast(ExNVR.PubSub, "detection", {:prediction, prediction, encoded_img})
    # IO.inspect("broadcast INFOOOOO #{prediction}")
    {[], %{state | label: prediction}}
  end

  defp load_model(%{model: nil} = state, model \\ "microsoft/resnet-50") do
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
    Membrane.Logger.debug("Model Serving")

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
