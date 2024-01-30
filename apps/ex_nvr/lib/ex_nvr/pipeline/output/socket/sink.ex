defmodule ExNVR.Pipeline.Output.Socket.Sink do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.RawVideo

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: %RawVideo{aligned: true, pixel_format: :RGB}

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{sockets: [], width: nil, height: nil}}
  end

  @impl true
  def handle_stream_format(:input, %RawVideo{} = format, _ctx, state) do
    {[], %{state | width: format.width, height: format.height}}
  end

  @impl true
  def handle_parent_notification({:new_socket, socket}, _ctx, state) do
    {[], %{state | sockets: [socket | state.sockets]}}
  end

  @impl true
  def handle_buffer(:input, _buffer, _ctx, %{sockets: []} = state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    message =
      <<System.os_time(:millisecond)::64, state.width::16, state.height::16, 3::8,
        buffer.payload::binary>>

    sockets =
      Enum.reduce(state.sockets, [], fn socket, open_sockets ->
        case :gen_tcp.send(socket, message) do
          {:error, :closed} -> open_sockets
          _other -> [socket | open_sockets]
        end
      end)

    if Enum.empty?(sockets) do
      {[notify_parent: :no_sockets], %{state | sockets: sockets}}
    else
      {[], %{state | sockets: sockets}}
    end
  end
end
