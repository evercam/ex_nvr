defmodule ExNVR.Elements.Image do
  @moduledoc """
  Element responsible for converting raw video frame to an
  image in JPEG or PNG format
  """

  use Membrane.Sink
  use Vix.Operator

  alias Membrane.RawVideo
  alias Vix.Vips

  def_input_pad :input,
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: %RawVideo{pixel_format: :I420},
    availability: :always

  def_options destination: [
                spec: binary() | {module(), atom(), list()},
                description: """
                The destination of the image, may be a file name or
                a {module, fun, args} tuple.

                If the value is a binary (filename), the files are generated using
                the following pattern `<file_name>_<n>.<format>`
                Where `n` is a counter that'll be incremented with each saved image.
                """
              ],
              format: [
                spec: :jpeg | :png,
                default: :jpeg,
                description: "The image format"
              ]

  @impl true
  def handle_init(_ctx, options) do
    {:ok, ycc_to_rgb_mat} =
      Vips.Image.new_from_list([
        [1.0, 0.0, 1.402],
        [1.0, -0.344136, -0.714136],
        [1.0, 1.772, 0.0]
      ])

    state =
      Map.from_struct(options)
      |> Map.merge(%{
        width: nil,
        height: nil,
        counter: 0,
        ycc_to_rgb: ycc_to_rgb_mat
      })

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, %RawVideo{width: width, height: height}, _ctx, state) do
    {[], %{state | width: width, height: height}}
  end

  @impl true
  def handle_write(:input, buffer, _ctx, state) do
    image = generate_image(state, buffer.payload)

    case state.destination do
      {module, fun, args} ->
        apply(module, fun, [Image.write!(image, :memory, suffix: "#{state.format}")] ++ args)
        {[], state}

      _ ->
        Image.write!(image, file_path(state))
        {[], %{state | counter: state.counter + 1}}
    end
  end

  defp generate_image(%{width: width, height: height, ycc_to_rgb: mat}, data) do
    y_size = width * height
    half_width = div(width, 2)
    half_height = div(height, 2)

    y =
      :binary.part(data, 0, y_size)
      |> new_from_binary(width, height)

    u =
      :binary.part(data, y_size, div(y_size, 4))
      |> new_from_binary(half_width, half_height)
      |> Vips.Operation.resize!(2.0, kernel: :VIPS_KERNEL_LINEAR)

    v =
      :binary.part(data, y_size + half_width * half_height, half_width * half_height)
      |> new_from_binary(half_width, half_height)
      |> Vips.Operation.resize!(2.0, kernel: :VIPS_KERNEL_LINEAR)

    (Vips.Operation.bandjoin!([y, u, v]) - [16, 128, 128])
    |> Vips.Operation.recomb!(mat)
    |> Vips.Operation.copy!(interpretation: :VIPS_INTERPRETATION_sRGB)
    |> Vips.Operation.cast!(:VIPS_FORMAT_UCHAR)
  end

  defp new_from_binary(binary, width, height) do
    {:ok, image} = Vips.Image.new_from_binary(binary, width, height, 1, :VIPS_FORMAT_UCHAR)
    image
  end

  defp file_path(state) do
    "#{state.destination}_#{state.counter}.#{state.format}"
  end
end
