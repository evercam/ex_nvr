defmodule ExNVR.Pipeline.Output.ObjectDetection.Sink do
  @moduledoc false

  use Membrane.Sink

  require Membrane.Logger

  alias Membrane.RawVideo

  def_input_pad :input, accepted_format: %RawVideo{}

  @impl true
  def handle_init(_ctx, _options) do
    {:ok, server_sock} = :gen_tcp.listen(5000, [:binary, active: false, reuseaddr: true])

    pid = self()

    spawn(fn ->
      accept_loop(server_sock, pid)
    end)

    {[], %{server_socket: server_sock, client_socket: nil, width: nil, height: nil}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    state = %{state | width: stream_format.width, height: stream_format.height}
    {[], state}
  end

  @impl true
  def handle_buffer(:input, _buffer, _ctx, %{client_socket: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    mat = Evision.Mat.from_binary(buffer.payload, :u8, 640, 640, 3)

    frame =
      buffer.metadata
      |> Map.get(:detections, [])
      |> Enum.reduce(
        mat,
        &Evision.rectangle(&2, {&1.xmin, &1.ymin}, {&1.xmax, &1.ymax}, {0, 255, 0})
      )
      |> Evision.Mat.to_binary()

    case :gen_tcp.send(state.client_socket, frame) do
      :ok -> {[], state}
      _error -> {[], %{state | client_socket: nil}}
    end
  end

  @impl true
  def handle_info({:socket, sock}, _ctx, state) do
    {[], %{state | client_socket: sock}}
  end

  defp accept_loop(server_sock, pid) do
    {:ok, sock} = :gen_tcp.accept(server_sock)
    send(pid, {:socket, sock})
    accept_loop(server_sock, pid)
  end
end
