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
      details: changeset_to_details(Changeset.traverse_errors(changeset, & &1))
    })
  end

  def call(conn, {:error, %Flop.Meta{errors: errors}}) do
    conn
    |> put_status(400)
    |> json(%{
      code: "BAD_ARGUMENT",
      message: "bad argument",
      details: changeset_to_details(errors)
    })
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(403)
    |> json(%{message: "Forbidden"})
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(500)
    |> json(%{
      code: "INTERNAL_ERROR",
      message: "internal server error",
      details: inspect(reason)
    })
  end

  defp changeset_to_details(errors) do
    errors
    |> Enum.flat_map(&map_error/1)
    |> Enum.map(fn {target, code, message} ->
      %{
        code: to_string(code) |> String.upcase(),
        target: target,
        message: message
      }
    end)
  end

  defp map_error({field, errors}) do
    errors = List.flatten(errors)

    case Keyword.keyword?(errors) do
      true ->
        Enum.flat_map(errors, &map_error/1)

      false ->
        Enum.map(errors, fn {msg, options} ->
          error_msg = format_error_message(msg, options)
          {field, options[:validation] || options[:constraint], error_msg}
        end)
    end
  end

  defp format_error_message(message, options) do
    Regex.replace(~r/%{(\w+)}/, message, fn _, key ->
      options
      |> Keyword.get(String.to_existing_atom(key), key)
      |> to_string()
    end)
  end
end
