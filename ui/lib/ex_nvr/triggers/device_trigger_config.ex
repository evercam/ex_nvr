defmodule ExNVR.Triggers.DeviceTriggerConfig do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "devices_trigger_configs" do
    belongs_to :device, ExNVR.Model.Device, primary_key: true
    belongs_to :trigger_config, ExNVR.Triggers.TriggerConfig, primary_key: true, type: :id
  end
end
