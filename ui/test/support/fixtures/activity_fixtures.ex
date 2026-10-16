defmodule ExNVR.ActivityFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Activity` context.
  """

  import ExUnit.Assertions
  import Ecto.Query

  alias ExNVR.Activity
  alias ExNVR.Activity.{Actor, Entry}
  alias ExNVR.Repo

  @spec valid_entry_attributes(map() | Keyword.t()) :: map()
  def valid_entry_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      category: :device,
      action: "device.updated",
      message: "Device updated",
      actor: %Actor{type: :user, label: "tester@example.com", ip: "127.0.0.1"}
    })
  end

  @doc """
  Inserts an entry directly, bypassing the writer.
  """
  @spec entry_fixture(map() | Keyword.t()) :: Entry.t()
  def entry_fixture(attrs \\ %{}) do
    {:ok, entry} = attrs |> valid_entry_attributes() |> Activity.build()
    entry |> Map.put(:id, nil) |> Repo.insert!()
  end

  @doc """
  Asserts an entry with the given action was logged and that its fields match.

  Returns the matching entry.
  """
  @spec assert_activity_logged(String.t(), map() | Keyword.t()) :: Entry.t()
  def assert_activity_logged(action, fields \\ %{}) do
    entries = Repo.all(from e in Entry, where: e.action == ^action, order_by: [desc: e.id])

    assert entries != [], "expected an activity entry with action #{inspect(action)}"

    entry =
      Enum.find(entries, fn entry ->
        Enum.all?(fields, fn {key, value} -> Map.get(entry, key) == value end)
      end)

    assert entry,
           "no #{inspect(action)} entry matches #{inspect(Map.new(fields))}, got: #{inspect(entries)}"

    entry
  end
end
