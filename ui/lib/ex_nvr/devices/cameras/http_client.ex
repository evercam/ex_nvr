defmodule ExNVR.Devices.Cameras.HttpClient do
  @moduledoc false

  alias ExNVR.Devices.Cameras.{DeviceInfo, StreamProfile}

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

  @optional_callbacks fetch_lpr_event: 2, device_info: 2, stream_profiles: 2

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour ExNVR.Devices.Cameras.HttpClient

      @impl true
      def fetch_lpr_event(_url, _opts), do: {:error, :not_implemented}

      @impl true
      def device_info(_url, _opts), do: {:error, :not_implemented}

      @impl true
      def stream_profiles(_url, _opts), do: {:error, :not_implemented}

      defoverridable fetch_lpr_event: 2, device_info: 2, stream_profiles: 2
    end
  end
end
