defmodule ExNVR.Activity.Diff do
  @moduledoc """
  Lists the fields that changed between two versions of a struct or map, with
  their new value only, previous values are not kept.

  Nested maps and embedded schemas are flattened into dotted keys:

      %{"name" => "Front Gate", "stream_config.stream_uri" => "rtsp://new"}

  Values of sensitive fields (passwords, secrets, tokens) are never included,
  only the fact that they changed.
  """

  @redacted "[REDACTED]"
  @sensitive_keys ~w(password hashed_password secret_access_key access_key_id token api_key)
  @ignored_keys ~w(__meta__ inserted_at updated_at)

  @type t :: %{String.t() => term()}

  @doc """
  Returns the fields that differ between `old` and `new`, with their value in `new`.

  Options:
    * `:redact` - additional keys whose values should be hidden.
    * `:ignore` - additional keys to skip.
  """
  @spec changes(map(), map(), Keyword.t()) :: t()
  def changes(old, new, opts \\ []) do
    redact = @sensitive_keys ++ Enum.map(Keyword.get(opts, :redact, []), &to_string/1)
    ignore = @ignored_keys ++ Enum.map(Keyword.get(opts, :ignore, []), &to_string/1)

    old = flatten(old, ignore)
    new = flatten(new, ignore)

    old
    |> Map.keys()
    |> Enum.concat(Map.keys(new))
    |> Enum.uniq()
    |> Enum.reject(&(Map.get(old, &1) == Map.get(new, &1)))
    |> Map.new(&{&1, value(&1, new[&1], redact)})
  end

  @doc """
  Returns a JSON friendly copy of `data` with the values of sensitive keys hidden.
  """
  @spec redact(map()) :: map()
  def redact(data), do: normalize(data)

  defp flatten(data, ignore, prefix \\ nil) do
    data
    |> to_map()
    |> Enum.reject(fn {key, value} ->
      to_string(key) in ignore or match?(%Ecto.Association.NotLoaded{}, value)
    end)
    |> Enum.flat_map(fn {key, value} ->
      key = if prefix, do: "#{prefix}.#{key}", else: to_string(key)

      if nested?(value),
        do: Map.to_list(flatten(value, ignore, key)),
        else: [{key, normalize(value)}]
    end)
    |> Map.new()
  end

  defp to_map(nil), do: %{}
  defp to_map(%_{} = struct), do: Map.from_struct(struct)
  defp to_map(map) when is_map(map), do: map

  defp nested?(%DateTime{}), do: false
  defp nested?(%NaiveDateTime{}), do: false
  defp nested?(%Date{}), do: false
  defp nested?(%Time{}), do: false
  defp nested?(value), do: is_map(value)

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize(%Date{} = value), do: Date.to_iso8601(value)
  defp normalize(%Time{} = value), do: Time.to_iso8601(value)
  defp normalize(%_{} = struct), do: struct |> Map.from_struct() |> normalize()

  defp normalize(map) when is_map(map) do
    map
    |> Map.drop([:__meta__])
    |> Map.new(fn {key, value} ->
      key = to_string(key)
      {key, if(key in @sensitive_keys and value != nil, do: @redacted, else: normalize(value))}
    end)
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value) when is_tuple(value), do: inspect(value)

  defp normalize(value) when is_atom(value) and value not in [nil, true, false],
    do: to_string(value)

  defp normalize(value), do: value

  defp value(_key, nil, _redact), do: nil

  defp value(key, value, redact) do
    if key |> String.split(".") |> List.last() |> Kernel.in(redact), do: @redacted, else: value
  end
end
