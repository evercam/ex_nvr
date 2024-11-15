defmodule ExNVR.BIF.Index do
  @moduledoc false

  @type timestamp :: non_neg_integer()
  @type image_size :: non_neg_integer()

  @type t :: %__MODULE__{
          entries: [{timestamp(), image_size()}]
        }

  defstruct entries: []

  @spec new() :: t()
  def new(), do: %__MODULE__{entries: []}

  @spec add_entry(t(), timestamp(), image_size()) :: t()
  def add_entry(%__MODULE__{} = index, timestamp, image_size) do
    %__MODULE__{
      index
      | entries: [{timestamp, image_size} | index.entries]
    }
  end

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{entries: entries}), do: length(entries)

  @spec serialize(t(), non_neg_integer()) :: binary()
  def serialize(%__MODULE__{} = index, starting_offset \\ 64) do
    starting_offset = (length(index.entries) + 1) * 8 + starting_offset

    Enum.reverse(index.entries)
    |> Kernel.++([{0xFFFFFFFF, 0}])
    |> Enum.reduce({<<>>, starting_offset}, fn {timestamp, size}, {result, previous_offset} ->
      acc = <<result::binary, timestamp::32-integer-little, previous_offset::32-integer-little>>
      {acc, previous_offset + size}
    end)
    |> elem(0)
  end
end
