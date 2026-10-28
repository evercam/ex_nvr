defmodule ExNVR.Export.Recent do
  @moduledoc """
  Exports started or resumed since the app booted, newest first. In memory
  only: the list is empty again after a restart.
  """

  use Agent

  @max_entries 20

  @type entry :: %{
          dest_dir: Path.t(),
          device_id: binary(),
          kind: :usb | :s3,
          updated_at: DateTime.t()
        }

  def start_link(_opts), do: Agent.start_link(fn -> [] end, name: __MODULE__)

  @spec track(entry()) :: :ok
  def track(entry) do
    Agent.update(__MODULE__, fn entries ->
      [entry | Enum.reject(entries, &(&1.dest_dir == entry.dest_dir))]
      |> Enum.take(@max_entries)
    end)
  end

  @spec list(pos_integer()) :: [entry()]
  def list(limit), do: Agent.get(__MODULE__, &Enum.take(&1, limit))

  @doc false
  def clear, do: Agent.update(__MODULE__, fn _entries -> [] end)
end
