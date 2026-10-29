defmodule ExNVR.Devices.Cameras.OSD do
  @moduledoc false

  @type t :: %__MODULE__{
          position: :top_left | :top_right | :bottom_left | :bottom_right,
          date_format: :ymd | :mdy | :dmy,
          font_size: :smallest | :small | :medium | :large | :largest | :auto
        }

  defstruct position: :top_left, date_format: :ymd, font_size: :medium
end
