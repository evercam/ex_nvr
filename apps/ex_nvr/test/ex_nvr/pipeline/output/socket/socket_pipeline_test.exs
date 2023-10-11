defmodule ExNVR.Pipeline.Output.SocketPipelineTest do
  @moduledoc false

  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias ExNVR.Pipeline.UnixSocketServer
  alias Membrane.Testing.Pipeline

  @fixture_path "../../../../fixtures/video-30-10s.h264" |> Path.expand(__DIR__)

  @moduletag :tmp_dir

  if :os.type() |> elem(0) == :unix do
    setup do
      path = Path.join(System.tmp_dir!(), "ex_nvr.sock")
      on_exit(fn -> File.rm!(path) end)

      %{path: path}
    end

    test "snapshots are sent to unix socket", %{path: socket_path} do
      {:ok, _server} = UnixSocketServer.start_link(path: socket_path)

      pid = start_pipeline()
      assert_pipeline_play(pid)

      {:ok, client_socket} = :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false])
      assert_receive {:new_socket, server_socket}

      send_buffer_actions =
        for buffer <- chunk_file(@fixture_path), do: {:buffer, {:output, buffer}}

      Pipeline.message_child(pid, :sink, {:new_socket, server_socket})
      Pipeline.message_child(pid, :source, send_buffer_actions ++ [end_of_stream: :output])
      assert_end_of_stream(pid, :parser)

      for _idx <- 1..300 do
        assert {:ok, <<width::16, height::16, channels::8>>} = :gen_tcp.recv(client_socket, 5)
        assert width == 640
        assert height == 480
        assert channels == 3

        assert {:ok, _data} = :gen_tcp.recv(client_socket, width * height * channels)
      end

      assert {:error, :timeout} = :gen_tcp.recv(client_socket, 0, 100)
      :gen_tcp.close(client_socket)

      Pipeline.terminate(pid)
    end

    defp start_pipeline() do
      structure = [
        child(:source, ExNVR.Support.TestSource)
        |> child(:parser, Membrane.H264.Parser)
        |> child(:sink, %ExNVR.Pipeline.Output.Socket{encoding: :H264})
      ]

      Pipeline.start_supervised!(structure: structure)
    end

    defp chunk_file(file_path) do
      File.read!(file_path)
      |> :binary.bin_to_list()
      |> Enum.chunk_every(10_000)
      |> Enum.map(&%Membrane.Buffer{payload: :binary.list_to_bin(&1)})
    end
  end
end
