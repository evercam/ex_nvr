defmodule ExNVR.AV.Hailo.API.VDevice do
  @moduledoc false

  defstruct ref: nil

  @type t :: %__MODULE__{ref: reference() | nil}
end
