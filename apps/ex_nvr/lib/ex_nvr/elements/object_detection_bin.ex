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
  def handle_setup(_ctx, state) do
    Membrane.Logger.debug("Setup the ObjectDetection element, start loading the Model")
    state =
      state
      |> load_model()
      |> load_featurizer()
      |> load_serving()

    {[notify_parent: {:pid, self()}], state}
  end
  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.debug("Initialize the Object Detection element")

    state =
      Map.from_struct(options)
      |> Map.merge(%{
        model: nil,
        featurizer: nil,
        serving: nil,
        label: nil,
        current_encoded_frame: nil
      })

    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, ref) = pad, ctx, state) do

    spec = [
      bin_input(pad)
      |> child({:decoder, ref}, %Membrane.H264.FFmpeg.Decoder{use_shm?: true})
      |> child(converter: %Membrane.FramerateConverter{framerate: {2, 1}})
      |> child(:scaler, %Membrane.FFmpeg.SWScale.Scaler{output_width: 224, output_height: 224}) # 224x224 image size for the model
      |> child(:converter, %Membrane.FFmpeg.SWScale.PixelFormatConverter{format: :I420})
      |> child({:filter, ref}, %ExNVR.Elements.OnePass{allow: ctx.options[:rank]})
      |> child({:jpeg, ref}, Turbojpeg.Filter)
      |> child({:sink, ref}, %ExNVR.Elements.Process.Sink{pid: self()})
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_element_end_of_stream({:sink, ref}, _pad, ctx, state) do
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
  def handle_info({:buffer, image}, _ctx, state) do
    IO.inspect("Handling INFOOOOO")
    prediction = predict(state.serving, image)
    encoded_img = encode_frame(image)
    {[notify_parent: {:detection, prediction}], %{state | current_encoded_frame: encoded_img}}
  end

  defp load_model(%{model: nil} = state, model \\ "microsoft/resnet-50") do
    Membrane.Logger.debug(
      "Load Model <<<#{model}>>>"
    )
    {:ok, model_info} = Bumblebee.load_model({:hf, model})
    %{state | model: model_info}
  end

  defp load_featurizer(%{model: _model, featurizer: nil} = state, featurizer \\ "microsoft/resnet-50") do
    Membrane.Logger.debug(
      "Load Model Featurizer <<<#{featurizer}>>>"
    )

    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "microsoft/resnet-50"})
    %{state | featurizer: featurizer}
  end

  defp load_serving(%{model: model, featurizer: featurizer, serving: nil} = state) do
    Membrane.Logger.debug(
      "Model Serving <<<Model: #{model}, Featurizer: #{featurizer}>>>"
    )
    serving = Bumblebee.Vision.image_classification(model, featurizer,
                top_k: 1,
                compile: [batch_size: 1],
                defn_options: [compiler: EXLA]
              )
     %{state | serving: serving}
  end

  defp encode_frame(frame) do
    Evision.imencode(".jpg", frame) |> Base.encode64()
  end

  defp predict(serving, frame) do
    tensor = frame |> Evision.Mat.to_nx() |> Nx.backend_transfer()

    %{predictions: [%{label: label}]} = Nx.Serving.run(serving, tensor)

    label
  end
end
