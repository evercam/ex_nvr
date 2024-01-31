defmodule ExNVR.Elements.SnapshotBin do
  @moduledoc """
  A bin element that receives an encoded video stream and create a snapshot in
  JPEG format by using the first or last access unit.

  Once the snapshot is created a parent notification is sent: `{:notify_parent, {:snapshot, snapshot}}`
  """

  use Membrane.Bin

  alias Membrane.{H264, H265}

  def_input_pad :input,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      ),
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
      ],
      encoding: [
        spec: ExNVR.Pipelines.Main.encoding(),
        description: "The video encoding"
      ]
    ]

  @impl true
  def handle_init(_ctx, _options) do
    {[], %{}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, ref) = pad, ctx, state) do
    decoder =
      case ctx.pad_options[:encoding] do
        :H264 -> %Membrane.H264.FFmpeg.Decoder{use_shm?: true}
        :H265 -> %Membrane.H265.FFmpeg.Decoder{use_shm?: true}
      end

    spec = [
      bin_input(pad)
      |> child({:decoder, ref}, decoder)
      |> child({:filter, ref}, %ExNVR.Elements.OnePass{allow: ctx.pad_options[:rank]})
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
    |> then(&{[remove_children: &1], state})
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:buffer, snapshot}, _ctx, state) do
    {[notify_parent: {:snapshot, snapshot}], state}
  end
end
