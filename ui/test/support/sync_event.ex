defmodule ExNVR.Support.SyncEvent do
  @moduledoc """
  A no-op event used in tests to signal that all the buffers sent before
  it were delivered downstream.

  Defined in `test/support` (and not in the test itself) so that it's
  compiled before the `Membrane.EventProtocol` protocol is consolidated.
  """

  @derive Membrane.EventProtocol

  defstruct []

  @type t :: %__MODULE__{}
end
