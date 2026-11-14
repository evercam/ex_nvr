defmodule ExNVR.Support.H26xParser do
  @moduledoc false

  # Splits an annexb byte stream into access units with generated timestamps

  use Membrane.Filter

  alias ExNVR.MediaUtils
  alias MediaCodecs.{H264, H265}

  def_input_pad :input, accepted_format: _any

  def_output_pad :output,
    accepted_format: any_of(%Membrane.H264{alignment: :au}, %Membrane.H265{alignment: :au})

  def_options codec: [spec: :h264 | :h265, default: :h264],
              framerate: [spec: {pos_integer(), pos_integer()}, default: {30, 1}]

  @impl true
  def handle_init(_ctx, opts) do
    {nalu_splitter, au_splitter} =
      case opts.codec do
        :h264 -> {H264.NaluSplitter.new(), H264.AccessUnitSplitter.new()}
        :h265 -> {H265.NaluSplitter.new(), H265.AccessUnitSplitter.new()}
      end

    {[],
     %{
       codec: opts.codec,
       framerate: opts.framerate,
       nalu_splitter: nalu_splitter,
       au_splitter: au_splitter,
       stream_format: nil,
       sent_format: nil,
       frame: 0
     }}
  end

  @impl true
  def handle_stream_format(:input, _format, _ctx, state), do: {[], state}

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    {nalus, nalu_splitter} = splitter(state.codec).process(buffer.payload, state.nalu_splitter)
    process_nalus(nalus, %{state | nalu_splitter: nalu_splitter})
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {actions, state} =
      state.nalu_splitter
      |> splitter(state.codec).flush()
      |> process_nalus(state)

    last_au = au_splitter(state.codec).flush(state.au_splitter)
    {last_actions, state} = au_actions(last_au, state)

    {actions ++ last_actions ++ [end_of_stream: :output], state}
  end

  defp process_nalus(nalus, state) do
    Enum.flat_map_reduce(nalus, state, fn nalu, state ->
      {au, au_splitter} = au_splitter(state.codec).process(nalu, state.au_splitter)
      au_actions(au, %{state | au_splitter: au_splitter})
    end)
  end

  defp au_actions(au, state) when au in [nil, []], do: {[], state}

  defp au_actions(au, state) do
    state = maybe_update_stream_format(au, state)
    {num, den} = state.framerate
    timestamp = div(state.frame * den * Membrane.Time.second(), num)
    nalu_mod = nalu(state.codec)
    key_frame? = Enum.any?(au, &nalu_mod.keyframe?/1)

    buffer = %Membrane.Buffer{
      payload: MediaUtils.to_annexb(au),
      pts: timestamp,
      dts: timestamp,
      metadata: %{state.codec => %{key_frame?: key_frame?}}
    }

    actions =
      if state.stream_format == state.sent_format,
        do: [buffer: {:output, buffer}],
        else: [stream_format: {:output, state.stream_format}, buffer: {:output, buffer}]

    {actions, %{state | frame: state.frame + 1, sent_format: state.stream_format}}
  end

  defp maybe_update_stream_format(au, state) do
    case Enum.find(au, &(nalu(state.codec).type(&1) == :sps)) do
      nil -> state
      sps -> %{state | stream_format: stream_format(state.codec, sps)}
    end
  end

  defp stream_format(:h264, sps) do
    sps = H264.NALU.parse(sps).content

    %Membrane.H264{
      alignment: :au,
      stream_structure: :annexb,
      width: H264.NALU.SPS.width(sps),
      height: H264.NALU.SPS.height(sps)
    }
  end

  defp stream_format(:h265, sps) do
    sps = H265.NALU.parse(sps).content

    %Membrane.H265{
      alignment: :au,
      stream_structure: :annexb,
      width: H265.NALU.SPS.width(sps),
      height: H265.NALU.SPS.height(sps)
    }
  end

  defp splitter(:h264), do: H264.NaluSplitter
  defp splitter(:h265), do: H265.NaluSplitter

  defp au_splitter(:h264), do: H264.AccessUnitSplitter
  defp au_splitter(:h265), do: H265.AccessUnitSplitter

  defp nalu(:h264), do: H264.NALU
  defp nalu(:h265), do: H265.NALU
end
