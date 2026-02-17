defmodule ExNVR.Nerves.RemoteConfigurer.Step do
  @moduledoc """
  Module describing a configuration step and its result.
  """

  @type t :: %__MODULE__{
          name: atom(),
          status: :ok | :error,
          reason: String.t() | nil
        }

  @derive Jason.Encoder
  defstruct [:name, :status, :reason]
end
