defmodule ExNVR.Pipeline.Output.SocketPipelineTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias ExNVR.{UnixSocketServer, Utils}
  alias Membrane.Testing.Pipeline

  @fixture_path "../../../../fixtures/video-30-10s.h264" |> Path.expand(__DIR__)

  @moduletag :tmp_dir

  if :os.type() |> elem(0) == :unix do
    test "snapshots are sent to unix socket", %{tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir)
      File.mkdir_p!(Utils.unix_socket_dir())
      Process.register(self(), Utils.pipeline_name(device))
      {:ok, _server} = UnixSocketServer.start_link(device: device)

      pid = start_pipeline()

      client_socket = open_client_socket(device, 3)

      assert_receive {:new_socket, server_socket}

      send_buffer_actions =
        for buffer <- chunk_file(@fixture_path), do: {:buffer, {:output, buffer}}

      Pipeline.notify_child(pid, :sink, {:new_socket, server_socket})
      Pipeline.notify_child(pid, :source, send_buffer_actions ++ [end_of_stream: :output])
      assert_end_of_stream(pid, :parser)

      for _idx <- 1..300 do
        assert {:ok, <<_timestamp_ms::64, width::16, height::16, channels::8>>} =
                 :gen_tcp.recv(client_socket, 13)

        assert width == 640
        assert height == 480
        assert channels == 3

        assert {:ok, _data} = :gen_tcp.recv(client_socket, width * height * channels)
      end

      assert {:error, :timeout} = :gen_tcp.recv(client_socket, 0, 100)
      :gen_tcp.close(client_socket)

      Pipeline.terminate(pid)
    end

    defp open_client_socket(_device, 0), do: raise("socket doesn't exists")

    defp open_client_socket(device, rety) do
      path = Utils.unix_socket_path(device.id)

      case :gen_tcp.connect({:local, path}, 0, [:binary, active: false]) do
        {:ok, socket} ->
          socket

        {:error, _reason} ->
          Process.sleep(200)
          open_client_socket(device, rety - 1)
      end
    end

    defp start_pipeline do
      spec = [
        child(:source, ExNVR.Support.TestSource)
        |> child(:parser, %Membrane.H264.Parser{
          generate_best_effort_timestamps: %{framerate: {1, 30}}
        })
        |> child(:sink, ExNVR.Pipeline.Output.Socket)
      ]

      Pipeline.start_supervised!(spec: spec)
    end

    defp chunk_file(file_path) do
      File.read!(file_path)
      |> :binary.bin_to_list()
      |> Enum.chunk_every(10_000)
      |> Enum.map(&%Membrane.Buffer{payload: :binary.list_to_bin(&1)})
    end
  end
end
