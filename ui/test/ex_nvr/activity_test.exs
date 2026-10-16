defmodule ExNVR.ActivityTest do
  use ExNVR.DataCase

  import ExNVR.{AccountsFixtures, ActivityFixtures}

  alias ExNVR.Activity
  alias ExNVR.Activity.{Actor, Entry}

  describe "log/1" do
    test "persists an entry with defaults" do
      assert :ok = Activity.log(valid_entry_attributes(action: "auth.login"))

      entry = assert_activity_logged("auth.login")
      assert entry.severity == :info
      assert entry.metadata == %{}
      assert %DateTime{} = entry.time
    end

    test "requires an actor" do
      assert {:error, changeset} =
               Activity.log(category: :auth, action: "auth.login", message: "Logged in")

      assert %{actor_type: ["can't be blank"]} = errors_on(changeset)
    end

    test "logs remote server actions" do
      :ok = Activity.log(valid_entry_attributes(category: :remote, actor: Actor.remote()))

      entry = assert_activity_logged("device.updated")
      assert entry.actor_type == :remote
      assert entry.actor_label == "remote server"
    end

    test "records the actor, device and resource" do
      user = user_fixture()
      device = %{id: Ecto.UUID.generate(), name: "Front Gate"}

      :ok =
        Activity.log(%{
          category: :device,
          action: "device.updated",
          message: "Device Front Gate updated",
          severity: :warning,
          actor: Actor.user(user, ip: {192, 168, 1, 10}),
          device: device,
          resource: %{type: "device", id: device.id, label: device.name},
          metadata: %{section: "general"}
        })

      entry = assert_activity_logged("device.updated")

      assert entry.severity == :warning
      assert entry.actor_type == :user
      assert entry.actor_id == user.id
      assert entry.actor_label == user.email
      assert entry.source_ip == "192.168.1.10"
      assert entry.device_id == device.id
      assert entry.device_name == "Front Gate"
      assert entry.resource_type == "device"
      assert entry.resource_id == device.id
      assert entry.resource_label == "Front Gate"
      assert entry.metadata == %{"section" => "general"}
    end

    test "returns an error on invalid attributes" do
      assert {:error, changeset} = Activity.log(category: :system, action: "x")
      assert %{category: ["is invalid"], message: ["can't be blank"]} = errors_on(changeset)
      assert Repo.aggregate(Entry, :count) == 0
    end

    test "keeps entries with non JSON metadata" do
      :ok =
        Activity.log(
          valid_entry_attributes(action: "export.failed", metadata: %{reason: {:error, :enoent}})
        )

      entry = assert_activity_logged("export.failed")
      assert entry.metadata["raw"] =~ ":enoent"
    end

    test "broadcasts new entries" do
      Activity.subscribe()
      :ok = Activity.log(valid_entry_attributes())

      assert_receive {:activity_logged, [%Entry{action: "device.updated"}]}
    end
  end

  test "log_sync/1 persists the entry" do
    assert :ok = Activity.log_sync(valid_entry_attributes(action: "auth.logout"))
    assert_activity_logged("auth.logout")
  end

  describe "list/2" do
    setup do
      device_id = Ecto.UUID.generate()
      now = DateTime.utc_now()

      old =
        entry_fixture(time: DateTime.add(now, -2, :hour), category: :auth, action: "auth.login")

      warning =
        entry_fixture(
          time: DateTime.add(now, -1, :hour),
          severity: :warning,
          device: %{id: device_id, name: "Cam"}
        )

      latest =
        entry_fixture(time: now, message: "Camera offline", device: %{id: device_id, name: "Cam"})

      %{device_id: device_id, entries: [old, warning, latest]}
    end

    test "returns the newest entries first", %{entries: [old, warning, latest]} do
      assert {:ok, {entries, meta}} = Activity.list(%{})
      assert Enum.map(entries, & &1.id) == [latest.id, warning.id, old.id]
      assert meta.total_count == 3
    end

    test "filters entries", %{entries: [old, warning, latest]} do
      assert {:ok, {[entry], _meta}} =
               Activity.list(%{filters: [%{field: :category, op: :==, value: "auth"}]})

      assert entry.id == old.id

      assert {:ok, {[entry], _meta}} =
               Activity.list(%{filters: [%{field: :severity, op: :!=, value: "info"}]})

      assert entry.id == warning.id

      assert {:ok, {[entry], _meta}} =
               Activity.list(%{filters: [%{field: :message, op: :like, value: "offline"}]})

      assert entry.id == latest.id
    end

    test "scopes entries to a device", %{device_id: device_id, entries: [_old, warning, latest]} do
      assert {:ok, {entries, _meta}} = Activity.list(%{}, device_id: device_id)
      assert Enum.map(entries, & &1.id) == [latest.id, warning.id]
    end

    test "paginates" do
      assert {:ok, {[_entry], meta}} = Activity.list(%{page: 2, page_size: 2})
      assert meta.total_pages == 2
    end
  end

  test "delete_older_than/1 deletes old entries only" do
    now = DateTime.utc_now()
    old = entry_fixture(time: DateTime.add(now, -31, :day))
    recent = entry_fixture(time: DateTime.add(now, -29, :day))

    assert Activity.delete_older_than(30) == 1

    refute Activity.get(old.id)
    assert Activity.get(recent.id)
  end
end
