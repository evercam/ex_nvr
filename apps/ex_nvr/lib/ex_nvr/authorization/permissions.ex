defmodule ExNVR.Authorization.Permissions do
  use Permit.Permissions, actions_module: ExNVR.Authorization.Actions

  def can(%{role: :admin} = _user) do
    permit()
    |> all(ExNVR.Model.Device)
    |> all(ExNVR.Model.Recording)
    |> all(ExNVR.Accounts.User)
  end

  def can(%{role: :user, id: user_id} = _user) do
    permit()
    |> read(ExNVR.Model.Device) # allows :index and :show
    |> access_device_stream(ExNVR.Model.Device) # allows actions in DeviceStreamingController
    |> read(ExNVR.Model.Recording)  # allows :index and :show
    |> access_footage_stream(ExNVR.Model.Recording) # allows actions in RecordingController
    |> all(ExNVR.Accounts.User, id: user_id)
  end

  def can(_user), do: permit()
end
