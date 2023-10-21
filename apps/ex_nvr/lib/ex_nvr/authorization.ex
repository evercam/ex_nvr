defmodule ExNVR.Authorization do
  use Permit, permissions_module: ExNVR.Authorization.Permissions
end
