defmodule ExNVRWeb.API.FallbackController do
  use ExNVRWeb, :controller

  import Plug.Conn

  alias Ecto.Changeset

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(404)
    |> json(%{message: "Resource doesn't exists"})
  end

  def call(conn, {:error, %Changeset{} = changeset}) do
    conn
    |> put_status(400)
    |> json(%{
      code: "BAD_ARGUMENT",
      message: "bad argument",
      details: changeset_to_details(changeset)
    })
  end

  def changeset_to_details(%Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(fn {msg, options} ->
      error_msg =
        Regex.replace(~r/%{(\w+)}/, msg, fn _, key ->
          options
          |> Keyword.get(String.to_existing_atom(key), key)
          |> to_string()
        end)

      [error_msg: error_msg, validation: options[:validation] || options[:constraint]]
    end)
    |> Enum.flat_map(&map_error/1)
    |> Enum.map(fn {target, code, message} ->
      %{
        code: to_string(code) |> String.upcase(),
        target: target,
        message: message
      }
    end)
  end

  defp map_error({_field, errors}) when is_map(errors), do: Enum.flat_map(errors, &map_error/1)
  defp map_error({field, errors}), do: Enum.map(errors, &{field, &1[:validation], &1[:error_msg]})
end
