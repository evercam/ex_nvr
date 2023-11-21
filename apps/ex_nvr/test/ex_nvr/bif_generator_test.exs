defmodule ExNVR.BifGeneratorTest do
  @moduledoc false

  use ExNVR.DataCase

  alias ExNVR.BifGeneratorServer

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    device = device_fixture(%{settings: %{storage_address: tmp_dir}})

    run_fixture(device,
      start_date: ~U(2023-08-10 10:15:10.000000Z),
      end_date: ~U(2023-08-10 10:54:19.000000Z)
    )

    run_fixture(device,
      start_date: ~U(2023-08-10 10:58:10.200000Z),
      end_date: ~U(2023-08-10 12:54:19.300000Z)
    )

    run =
      run_fixture(device,
        start_date: ~U(2023-08-12 14:15:10.000000Z),
        end_date: ~U(2023-08-12 16:17:10.000000Z)
      )

    {:ok, device: device, run: run}
  end

  test "list hours", %{device: device} do
    assert [
             ~U(2023-08-10 10:00:00Z),
             ~U(2023-08-10 11:00:00Z),
             ~U(2023-08-10 12:00:00Z),
             ~U(2023-08-12 14:00:00Z),
             ~U(2023-08-12 15:00:00Z),
             ~U(2023-08-12 16:00:00Z)
           ] = BifGeneratorServer.list_hours(device)

    ExNVR.Utils.bif_dir(device)
    |> Path.join("2023081214.bif")
    |> File.touch!()

    assert [~U(2023-08-12 15:00:00Z), ~U(2023-08-12 16:00:00Z)] =
             BifGeneratorServer.list_hours(device)
  end

  test "generate bif files", %{device: device, run: run} do
    ExNVR.Utils.bif_dir(device)
    |> Path.join("2023081214.bif")
    |> File.touch!()

    hours = [~U(2023-08-12 15:00:00Z), ~U(2023-08-12 16:00:00Z)]

    recording_fixture(device,
      start_date: ~U(2023-08-12 15:15:00Z),
      end_date: ~U(2023-08-12 15:15:05Z),
      run: run
    )

    recording_fixture(device,
      start_date: ~U(2023-08-12 16:15:00Z),
      end_date: ~U(2023-08-12 16:15:05Z),
      run: run
    )

    assert {:ok, state} = BifGeneratorServer.init(device: device)
    assert {:noreply, ^state} = BifGeneratorServer.handle_info(:tick, state)

    bif_dir = ExNVR.Utils.bif_dir(device)

    for hour <- hours do
      filename = Calendar.strftime(hour, "%Y%m%d%H.bif")
      assert File.exists?(Path.join(bif_dir, filename))
    end
  end
end
