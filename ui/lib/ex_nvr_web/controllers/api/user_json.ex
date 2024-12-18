defmodule ExNVRWeb.API.UserJSON do
  @moduledoc false

  @spec show(map()) :: map()
  def show(%{user_instance: user_instance}) do
    serialize_user(user_instance)
  end

  def list(%{users: users}) do
    Enum.map(users, &serialize_user/1)
  end

  defp serialize_user(user) do
    user
    |> Map.from_struct()
    |> Map.take([:id, :first_name, :last_name, :username, :email, :role, :language])
  end
end
