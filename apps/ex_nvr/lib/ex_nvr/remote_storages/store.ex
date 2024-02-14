defmodule ExNVR.RemoteStorages.Store do
  @moduledoc false

  alias ExNVR.Model.{Device, Recording}

  @callback save_recording(Device.t(), Recording.t(), opts :: Keyword.t()) ::
              :ok | {:error, any()}
end
