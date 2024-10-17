defmodule ExNVR.Onvif.Utils do
  @moduledoc false

  @doc """
  Delete namespaces from the converted XML
  """
  @spec delete_namespaces(map()) :: map()
  def delete_namespaces(response) when is_map(response) do
    Enum.reduce(response, %{}, fn {key, value}, acc ->
      Map.put(acc, delete_namespace(key), delete_namespaces(value))
    end)
  end

  def delete_namespaces(response) when is_list(response) do
    Enum.map(response, &delete_namespaces/1)
  end

  def delete_namespaces({key, value}) do
    {delete_namespace(key), delete_namespaces(value)}
  end

  def delete_namespaces(response), do: response

  defp delete_namespace(key) do
    to_string(key)
    |> String.split(":")
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
