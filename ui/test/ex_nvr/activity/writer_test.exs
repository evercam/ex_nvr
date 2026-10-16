defmodule ExNVR.Activity.WriterTest do
  use ExNVR.DataCase

  import ExNVR.ActivityFixtures

  alias ExNVR.Activity
  alias ExNVR.Activity.{Entry, Writer}

  @name :test_activity_writer

  defp start_writer(opts \\ []) do
    opts = Keyword.merge([name: @name, flush_interval: :timer.minutes(10), max_batch: 3], opts)
    start_supervised!({Writer, opts})
  end

  defp entry(action) do
    {:ok, entry} = Activity.build(valid_entry_attributes(action: action))
    entry
  end

  defp count, do: Repo.aggregate(Entry, :count)

  test "buffers entries until flushed" do
    start_writer()

    Writer.write(@name, entry("a"))
    Writer.write(@name, entry("b"))
    :sys.get_state(@name)

    assert count() == 0
    assert :ok = Writer.flush(@name)
    assert count() == 2
  end

  test "writes a batch once full" do
    start_writer()

    for action <- ~w(a b c), do: Writer.write(@name, entry(action))
    :sys.get_state(@name)

    assert count() == 3
  end

  test "flushes on interval" do
    Activity.subscribe()
    start_writer(flush_interval: 10)

    Writer.write(@name, entry("a"))

    assert_receive {:activity_logged, [%Entry{action: "a"}]}, 1_000
    assert count() == 1
  end

  test "write_sync/2 persists buffered entries" do
    start_writer()

    Writer.write(@name, entry("a"))
    assert :ok = Writer.write_sync(@name, entry("b"))

    assert count() == 2
  end

  test "flushes when stopped" do
    start_writer()

    Writer.write(@name, entry("a"))
    stop_supervised!(Writer)

    assert count() == 1
  end

  test "drops the oldest entries when the buffer is full" do
    start_writer(max_buffer: 2, max_batch: 10)

    for action <- ~w(a b c), do: Writer.write(@name, entry(action))
    Writer.flush(@name)

    assert Repo.all(from e in Entry, select: e.action, order_by: e.id) == ~w(b c)
  end
end
