defmodule ExNVR.Pipeline.Event.StreamClosed do
  @moduledoc """
  An event sent when a connection (or media stream connection) is lost or closed.
  """

  @derive Membrane.EventProtocol

  defstruct []

  @type t :: %__MODULE__{}
end
