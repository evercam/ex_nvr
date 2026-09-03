defmodule ExNVR.BIF.GeneratorServerTest do
  @moduledoc false

  use ExNVR.DataCase

  alias ExNVR.BIF.GeneratorServer
  alias ExNVR.Model.Device

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    device = camera_device_fixture(tmp_dir, %{settings: %{generate_bif: true}})
    {:ok, device: device}
  end

  test "generate bif files", %{device: device} do
    current_hour = DateTime.utc_now() |> DateTime.to_unix()
    current_hour = current_hour - rem(current_hour, 3600)

    for seconds <- -7200..100//200 do
      path = Path.join(Device.bif_thumbnails_dir(device), "#{current_hour + seconds}.jpg")
      File.write!(path, String.duplicate(<<0, 1>>, 100))
    end

    hours = [
      DateTime.from_unix!(current_hour) |> DateTime.add(-7200),
      DateTime.from_unix!(current_hour) |> DateTime.add(-3600)
    ]

    assert {:ok, state} = GeneratorServer.init(device: device)
    assert {:noreply, ^state} = GeneratorServer.handle_info(:tick, state)

    bif_dir = Device.bif_dir(device)

    for hour <- hours do
      filename = Calendar.strftime(hour, "%Y%m%d%H.bif")
      assert File.exists?(Path.join(bif_dir, filename))
    end
  end
end
