defmodule ExNVR.Triggers.TriggerTarget do
  @moduledoc """
  Behaviour for trigger target types.

  A trigger target defines an action to take when a trigger fires.
  For example, logging a message or starting recording on a device.
  """

  @type config_field :: %{
          name: atom(),
          type: :string | :integer | :select,
          label: String.t(),
          required: boolean(),
          default: any(),
          placeholder: String.t() | nil,
          options: [{String.t(), String.t()}] | nil
        }

  @callback label() :: String.t()
  @callback config_fields() :: [config_field()]
  @callback validate_config(map()) :: {:ok, map()} | {:error, Keyword.t()}
  @callback execute(trigger :: term(), config :: map(), opts :: keyword()) ::
              :ok | {:error, term()}
end
