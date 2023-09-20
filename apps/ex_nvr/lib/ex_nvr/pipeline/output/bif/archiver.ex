defmodule ExNVR.Pipeline.Output.Bif.Archiver do
  @moduledoc """
  Archive still images in a BIF file
  """

  use Membrane.Filter

  alias ExNVR.Pipeline.Output.Bif.Archiver.Index
  alias Membrane.{Buffer, RemoteStream}

  @magic_number <<0x89, 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A>>
  @version <<0::32>>
  @reserverd <<0::44*8>>

  def_input_pad :input,
    demand_mode: :auto,
    demand_unit: :buffers,
    accepted_format: _any,
    availability: :always

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: _any,
    availability: :always

  @impl true
  def handle_init(_ctx, _options) do
    {[],
     %{
       count_images: 0,
       index: Index.new()
     }}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[
       stream_format: {:output, %RemoteStream{type: :bytestream}},
       buffer: {:output, %Buffer{payload: @magic_number <> @version}}
     ], state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, %{index: index} = state) do
    timestamp = Membrane.Time.round_to_seconds(buffer.pts)
    index = Index.add_entry(index, timestamp, byte_size(buffer.payload))

    {[buffer: {:output, buffer}], %{state | index: index, count_images: state.count_images + 1}}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {[
       event: {:output, %Membrane.File.SeekSinkEvent{position: {:bof, 12}, insert?: true}},
       buffer: {:output, %Buffer{payload: build_rest_of_header(state)}},
       end_of_stream: :output
     ], state}
  end

  defp build_rest_of_header(state) do
    index_table = Index.serialize(state.index)
    <<state.count_images::32-integer-little, 0::32, @reserverd::binary, index_table::binary>>
  end
end
