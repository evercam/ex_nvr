defmodule ExNVR.Authorization.Actions do
  use Permit.Actions

  @impl Permit.Actions
  def grouping_schema do
    crud_grouping() # Includes :create, :read, :update and :delete
    |> Map.merge(%{
      #a 'plain' action has an empty [] not dependent on any other one, i.e. permission to these can be assigned directly
      # open: [],

      # Live View and Basic Controller Actions
      index: [:read],
      show: [:read],
      list: [:read],
      new: [:read],
      edit: [:read, :update],

      onvif_discovery: [:create, :read],

      # API Actions
      # Set custom actions to use for the proper endpoints
      access_device_stream: [],
      access_footage_stream: [],

      # Endpoints actions
      hls_stream: [:access_device_stream],
      snapshot: [:access_device_stream],
      hls_stream_segment: [:access_device_stream],

      footage: [:access_device_stream],
      bif: [:access_device_stream],

      blob: [:access_footage_stream],
    })
  end
end
