defmodule ExNVR.Pipelines.BifGeneratorTest do
  @moduledoc false

  use ExNVR.DataCase

  alias Membrane.Testing

  @moduletag :tmp_dir

  setup do
    device = device_fixture()
    File.mkdir_p!(ExNVR.Utils.recording_dir(device))

    recording_fixture(device,
      start_date: ~U(2023-06-23 10:00:00Z),
      end_date: ~U(2023-06-23 10:00:05Z)
    )

    recording_fixture(device,
      start_date: ~U(2023-06-23 10:00:05Z),
      end_date: ~U(2023-06-23 10:00:10Z)
    )

    recording_fixture(device,
      start_date: ~U(2023-06-23 10:00:10Z),
      end_date: ~U(2023-06-23 10:00:15Z)
    )

    {:ok, device: device}
  end

  test "generate BIF files", %{device: device, tmp_dir: tmp_dir} do
    out_file = Path.join(tmp_dir, "generated.bif")

    pid =
      prepare_pipeline(device,
        start_date: ~U(2023-06-23 10:00:03Z),
        end_date: ~U(2023-06-23 10:00:15Z),
        location: out_file
      )

    assert_pipeline_play(pid)
    assert_pipeline_notified(pid, :bif, :end_of_stream)

    assert File.exists?(out_file)

    assert <<0x89, 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A, 0::32, _::64, 0::44*8,
             _rest::binary>> =
             File.read!(out_file)
  end

  defp prepare_pipeline(device, options) do
    options = [
      module: ExNVR.Pipelines.BifGenerator,
      custom_args: Keyword.merge([device: device], options)
    ]

    Testing.Pipeline.start_supervised!(options)
  end
end
