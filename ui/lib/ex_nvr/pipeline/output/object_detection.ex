defmodule ExNVR.Pipeline.Output.ObjectDetection do
  @moduledoc false

  use Membrane.Bin

  require ExNVR.Utils
  require Membrane.Logger

  alias Membrane.{H264, H265}

  def_input_pad :input,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      )

  def_options hef_file: [
                spec: Path.t()
              ]

  @impl true
  def handle_init(_ctx, options) do
    spec = [
      bin_input()
      |> child(:decoder, __MODULE__.Decoder)
      |> child(:object_detector, %__MODULE__.Inferer{hef_file: options.hef_file})
      |> child(:sink, __MODULE__.Sink)
    ]

    {[spec: spec], %{}}
  end
end
