defmodule ExNVR.Pipeline.BIF.IndexTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.BIF.Index

  test "serialize entries" do
    index = Index.new()

    result =
      Index.add_entry(index, 0, 1000)
      |> Index.add_entry(1, 2000)
      |> Index.add_entry(2, 3500)
      |> Index.serialize(10)

    assert <<0::32, 42::32-integer-little, 1::32-integer-little, 1042::32-integer-little,
             2::32-integer-little, 3042::32-integer-little, 0xFFFFFFFF::32,
             6542::32-integer-little>> = result
  end
end
