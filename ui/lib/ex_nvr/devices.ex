defmodule ExNVR.Devices do
  @moduledoc """
  Context to manipulate devices
  """

  require Logger

  alias __MODULE__.{Onvif, Supervisor}
  alias Ecto.Multi
  alias ExNVR.Model.{Device, Recording, Run}
  alias ExNVR.{HTTP, Pipelines, Repo}
  alias ExNVR.Devices.Cameras.HttpClient.{Axis, Hik, Milesight}

  import Ecto.Query

  @spec create(map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    Multi.new()
    |> Multi.insert(:device, Device.create_changeset(params))
    |> Multi.run(:create_directories, fn _repo, %{device: device} ->
      create_device_directories(device)
      copy_device_file(device)
      {:ok, nil}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{device: device}} ->
        start_or_stop_supervisor(device, nil)
        {:ok, device}

      {:error, :device, changeset, _} ->
        {:error, changeset}
    end
  end

  @spec update(Device.t(), map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update(%Device{} = device, params) do
    device
    |> Device.update_changeset(params)
    |> Repo.update()
    |> case do
      {:ok, updated_device} ->
        start_or_stop_supervisor(device, updated_device)
        {:ok, updated_device}

      error ->
        error
    end
  end

  @spec update_state(Device.t(), Device.state()) ::
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update_state(%Device{} = device, state), do: __MODULE__.update(device, %{state: state})

  @spec list() :: [Device.t()]
  @spec list(map() | Keyword.t()) :: [Device.t()]
  def list(params \\ %{}), do: Repo.all(Device.filter(params) |> order_by([d], d.inserted_at))

  @spec ip_cameras :: [Device.t()]
  def ip_cameras, do: list(%{type: :ip})

  @spec get(binary()) :: Device.t() | nil
  def get(device_id), do: Repo.get(Device, device_id)

  @spec get!(binary()) :: Device.t()
  def get!(device_id) do
    case get(device_id) do
      %Device{} = device -> device
      nil -> raise "device does not exists"
    end
  end

  @spec delete(Device.t()) ::
          :ok | {:error, Ecto.Changeset.t()}
  def delete(device) do
    start_or_stop_supervisor(nil, device)

    Multi.new()
    |> Multi.delete_all(:recordings, Recording.with_device(device.id))
    |> Multi.delete_all(:runs, Run.with_device(device.id))
    |> Multi.delete(:device, device)
    |> Repo.transaction()
    |> case do
      {:ok, _} -> :ok
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  @spec change_device_creation(Device.t(), map()) :: Ecto.Changeset.t()
  def change_device_creation(%Device{} = device, attrs \\ %{}) do
    Device.create_changeset(device, attrs)
  end

  @spec change_device_update(Device.t(), map()) :: Ecto.Changeset.t()
  def change_device_update(%Device{} = device, attrs \\ %{}) do
    Device.update_changeset(device, attrs)
  end

  @spec fetch_snapshot(Device.t()) :: {:ok, binary} | {:error, term()}
  def fetch_snapshot(%{stream_config: %{snapshot_uri: nil}}) do
    {:error, :no_snapshot_uri}
  end

  def fetch_snapshot(%Device{credentials: credentials} = device) do
    opts = [username: credentials.username, password: credentials.password]
    url = device.stream_config.snapshot_uri

    case HTTP.get(url, opts) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, response} ->
        Logger.error("""
        Devices: could not fetch live snapshot"
        #{inspect(response)}
        """)

        {:error, response}

      error ->
        Logger.error("""
        Devices: could not fetch live snapshot"
        #{inspect(error)}
        """)

        error
    end
  end

  @spec create_device_directories(ExNVR.Model.Device.t()) :: :ok
  def create_device_directories(device) do
    File.mkdir_p!(Device.base_dir(device))
    File.mkdir_p!(Device.recording_dir(device))
    File.mkdir_p!(Device.recording_dir(device, :low))
    File.mkdir_p!(Device.bif_dir(device))
    File.mkdir_p!(Device.bif_thumbnails_dir(device))
    File.mkdir_p!(Device.lpr_thumbnails_dir(device))
  end

  @spec summary :: list()
  def summary do
    list()
    |> Task.async_stream(
      fn device ->
        Map.take(device, [:id, :name, :state, :type])
        |> Map.put(:stream_stats, stream_stats(device))
        |> Map.merge(Onvif.all_config(device))
      end,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  # IP cameras calls
  def device_info(device) do
    with {:ok, module} <- camera_module(Device.vendor(device)),
         {:ok, {url, opts}} <- url_and_opts(device) do
      module.device_info(url, opts)
    end
  end

  def stream_profiles(device) do
    with {:ok, module} <- camera_module(Device.vendor(device)),
         {:ok, {url, opts}} <- url_and_opts(device) do
      module.stream_profiles(url, opts)
    end
  end

  def fetch_lpr_event(device, last_event_timestamp \\ nil) do
    with {:ok, {url, opts}} <- url_and_opts(device) do
      opts = opts ++ [last_event_timestamp: last_event_timestamp, timezone: device.timezone]

      vendor = Device.vendor(device)
      camera_module!(vendor).fetch_lpr_event(url, opts)
    end
  end

  # Supervisor functions
  @spec start_all :: :ok
  def start_all do
    if run_pipeline?() do
      list()
      |> Enum.filter(&Device.recording?/1)
      |> Enum.each(&Supervisor.start/1)
    end

    :ok
  end

  defp start_or_stop_supervisor(%Device{} = device, nil) do
    if device.state != :stopped and run_pipeline?(), do: Supervisor.start(device)
  end

  defp start_or_stop_supervisor(nil, %Device{} = device) do
    Supervisor.stop(device)
  end

  defp start_or_stop_supervisor(%Device{} = device, %Device{} = updated_device) do
    cond do
      not run_pipeline?() ->
        :ok

      device.state != updated_device.state and not Device.recording?(updated_device) ->
        Supervisor.stop(updated_device)

      device.state != updated_device.state and Device.recording?(updated_device) ->
        Supervisor.start(updated_device)

      Device.config_updated(device, updated_device) and Device.recording?(updated_device) ->
        Supervisor.restart(updated_device)

      true ->
        :ok
    end
  end

  defp copy_device_file(%Device{type: :file, stream_config: stream_config} = device) do
    File.cp!(stream_config.temporary_path, Device.file_location(device))
  end

  defp copy_device_file(_device), do: :ok

  defp url_and_opts(%{url: nil}), do: {:error, :url_not_configured}

  defp url_and_opts(device) do
    %{username: username, password: password} = device.credentials
    auth_type = if not is_nil(username) && not is_nil(password), do: :basic
    http_url = Device.http_url(device)

    opts =
      [
        username: username,
        password: password,
        auth_type: auth_type
      ]

    {:ok, {http_url, opts}}
  end

  defp camera_module(:axis), do: {:ok, Axis}
  defp camera_module(:hik), do: {:ok, Hik}
  defp camera_module(:milesight), do: {:ok, Milesight}
  defp camera_module(_vendor), do: {:error, :not_implemented}

  defp camera_module!(vendor) do
    case camera_module(vendor) do
      {:ok, module} ->
        module

      _error ->
        raise "Not implementation module is found for #{inspect(vendor)}"
    end
  end

  defp stream_stats(device) do
    if Device.streaming?(device) do
      Pipelines.Main.get_tracks(device)
    end
  end

  defp run_pipeline?, do: ExNVR.Utils.run_main_pipeline?()
end
