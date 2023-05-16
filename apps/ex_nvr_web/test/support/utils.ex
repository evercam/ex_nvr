defmodule ExNVRWeb.Testing.Utils do
  def create_device(overrides \\ []) do
    device_params = %{
      id: UUID.uuid4(),
      name: "Device_#{System.unique_integer([:monotonic, :positive])}",
      type: "IP",
      config: %{
        stream_uri: "rtsp://localhost:554/my_device_stream",
        username: "user",
        password: "pass"
      }
    }

    params = Map.merge(device_params, Map.new(overrides))
    ExNVR.Devices.create(params)
  end

  def create_device!(overrides \\ []) do
    case create_device(overrides) do
      {:ok, device} ->
        device

      error ->
        raise """
          could not create a device
          #{inspect(error)}
        """
    end
  end

  def create_recording(overrides \\ []) do
    start_date = Faker.DateTime.backward(1)

    recording_params = %{
      start_date: start_date,
      end_date: DateTime.add(start_date, :rand.uniform(10) + 60)
    }

    params = Map.merge(recording_params, Map.new(overrides))
    ExNVR.Recordings.create(params)
  end

  def create_recording!(overrides \\ []) do
    case create_recording(overrides) do
      {:ok, recording} ->
        recording

      error ->
        raise """
          could not create a recording
          #{inspect(error)}

        """
    end
  end

  def create_temp_file!(content) do
    path = Path.join(System.tmp_dir!(), UUID.uuid4())
    File.write!(path, content)
    path
  end

  def clean_recording_directory(),
    do: File.rm_rf!(Application.get_env(:ex_nvr, :recording_directory))
end
