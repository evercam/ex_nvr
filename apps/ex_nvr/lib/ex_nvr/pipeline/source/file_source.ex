defmodule ExNVR.Pipeline.Source.FileSource do
  @moduledoc """
  Element that reads video data from a video file location
  """

  use Membrane.Source
  use Bunch.Access

  require Membrane.Logger

  alias Membrane.{Buffer, RemoteStream}

  def_options file_path: [
                spec: String.t(),
                default: "",
                description: "Path to the MP4 video file"
              ]

  def_output_pad :output,
    accepted_format: %RemoteStream{type: :packetized},
    mode: :push,
    availability: :on_request

  @impl true
  def handle_init(_context, %__MODULE__{} = options) do
    {[],
     %{
       file_path: options[:file_path],
       buffers: [],
       play?: false,
       output_pad: nil,
       file: nil
     }}
  end

  @impl true
  def handle_setup(_context, state) do
    {[], do_handle_setup(state)}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, _ref) = pad, _ctx, state) do
    buffers = Enum.map(state.buffers, &{:buffer, {pad, &1}}) |> Enum.reverse()
    state = %{state | output_pad: pad, play?: true}
    {[stream_format: {pad, %RemoteStream{type: :packetized}}] ++ buffers, state}
  end

  @impl true
  def handle_info({:media_packet, _channel, packet}, _ctx, %{play?: true} = state) do
    {[buffer: {state.output_pad, wrap_in_buffer(packet)}], state}
  end

  @impl true
  def handle_info({:media_packet, _channel, packet}, _ctx, state) do
    {[], %{state | buffers: [wrap_in_buffer(packet) | state.buffers]}}
  end

  @impl true
  def handle_info(_other, _context, state) do
    {[], state}
  end

  defp do_handle_setup(state) do
    {:ok, file} =
      File.open(state[:file_path], [:read, :raw])

    %{state | file: file, play?: true, output_pad: nil}
  end

  defp wrap_in_buffer(packet) do
    %Buffer{payload: packet, metadata: %{arrival_ts: Membrane.Time.os_time()}}
  end
end
