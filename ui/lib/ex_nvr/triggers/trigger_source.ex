defmodule ExNVR.Triggers.TriggerSource do
  @moduledoc """
  Behaviour for trigger source types.

  A trigger source defines what kind of input can activate a trigger.
  For example, an "event" source matches webhook events by type.
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
  @callback matches?(config :: map(), message :: term()) :: boolean()
end
