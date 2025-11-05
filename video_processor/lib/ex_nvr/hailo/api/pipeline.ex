defmodule ExNVR.AV.Hailo.API.Pipeline do
  @moduledoc """
  Represents an inference pipeline.
  """
  defstruct ref: nil,
            network_group_ref: nil,
            input_vstream_infos: [],
            output_vstream_infos: []

  @type t :: %__MODULE__{
          ref: reference(),
          network_group_ref: reference(),
          input_vstream_infos: [ExNVR.AV.Hailo.API.VStreamInfo.t()],
          output_vstream_infos: [ExNVR.AV.Hailo.API.VStreamInfo.t()]
        }
end
