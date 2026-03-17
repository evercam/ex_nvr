defmodule ExNVR.AV.Hailo.Model do
  @moduledoc false

  defstruct pipeline: nil,
            name: nil

  @type t :: %__MODULE__{
          pipeline: ExNVR.AV.Hailo.API.Pipeline.t(),
          name: String.t()
        }
end
