defmodule ExNVR.AV.Hailo.Model do
  @moduledoc """
  Represents a loaded Hailo model, ready for inference.
  This struct encapsulates the inference pipeline and associated metadata.
  """
  defstruct pipeline: nil,
            # e.g., HEF filename or a custom model name
            name: nil

  @type t :: %__MODULE__{
          pipeline: NxHailo.Hailo.API.Pipeline.t(),
          name: String.t()
        }
end
