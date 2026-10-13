defmodule ExNVR.Devices.Cameras.HttpClient do
  @moduledoc false

  alias ExNVR.Devices.Cameras.{DeviceInfo, RemoteRecording, StreamProfile}

  @type url :: binary()
  @type camera_opts :: Keyword.t()
  @type error :: {:error, {status :: non_neg_integer(), resp :: any()}} | {:error, any()}

  @doc """
  Fetch LPR (Detected License Plate) events from the camera.
  """
  @callback fetch_lpr_event(url(), camera_opts()) :: {:ok, [map()], [binary() | nil]} | error()

  @doc """
  Fetch basic camera information
  """
  @callback device_info(url(), camera_opts()) :: {:ok, DeviceInfo.t()} | error()

  @doc """
  Fetch stream profiles from camera.
  """
  @callback stream_profiles(url(), camera_opts()) :: {:ok, [StreamProfile.t()]} | error()

  @doc """
  Set stream profile on camera.
  """
  @callback set_stream_profile(url(), StreamProfile.t(), camera_opts()) :: {:ok, map()} | error()

  @doc """
  List recordings stored on the camera (e.g. SD card) between the given dates.
  """
  @callback list_recordings(url(), DateTime.t(), DateTime.t(), camera_opts()) ::
              {:ok, [RemoteRecording.t()]} | error()

  @doc """
  Download a recording stored on the camera to the given file path.
  """
  @callback download_recording(url(), RemoteRecording.t(), Path.t(), camera_opts()) ::
              :ok | error()

  @optional_callbacks fetch_lpr_event: 2,
                      device_info: 2,
                      stream_profiles: 2,
                      set_stream_profile: 3,
                      list_recordings: 4,
                      download_recording: 4

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour ExNVR.Devices.Cameras.HttpClient

      @impl true
      def fetch_lpr_event(_url, _opts), do: {:error, :not_implemented}

      @impl true
      def device_info(_url, _opts), do: {:error, :not_implemented}

      @impl true
      def stream_profiles(_url, _opts), do: {:error, :not_implemented}

      @impl true
      def set_stream_profile(_url, _profile, _opts), do: {:error, :not_implemented}

      @impl true
      def list_recordings(_url, _start_date, _end_date, _opts), do: {:error, :not_implemented}

      @impl true
      def download_recording(_url, _recording, _dest, _opts), do: {:error, :not_implemented}

      defoverridable fetch_lpr_event: 2,
                     device_info: 2,
                     stream_profiles: 2,
                     set_stream_profile: 3,
                     list_recordings: 4,
                     download_recording: 4
    end
  end
end
