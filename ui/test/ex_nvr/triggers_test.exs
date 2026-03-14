defmodule ExNVR.TriggersTest do
  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.TriggersFixtures

  alias ExNVR.Triggers
  alias ExNVR.Triggers.{TriggerConfig, TriggerSourceConfig, TriggerTargetConfig}

  @moduletag :tmp_dir

  setup ctx do
    %{device: camera_device_fixture(ctx.tmp_dir)}
  end

  describe "trigger config CRUD" do
    test "create a trigger config" do
      assert {:ok, %TriggerConfig{name: "my trigger"}} =
               Triggers.create_trigger_config(%{name: "my trigger"})
    end

    test "require name" do
      assert {:error, changeset} = Triggers.create_trigger_config(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforce unique name" do
      {:ok, _} = Triggers.create_trigger_config(%{name: "unique_trigger"})
      {:error, changeset} = Triggers.create_trigger_config(%{name: "unique_trigger"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "update a trigger config" do
      trigger = trigger_config_fixture(%{name: "original"})
      {:ok, updated} = Triggers.update_trigger_config(trigger, %{name: "updated"})
      assert updated.name == "updated"
    end

    test "delete a trigger config" do
      trigger = trigger_config_fixture()
      assert {:ok, _} = Triggers.delete_trigger_config(trigger)
      assert_raise Ecto.NoResultsError, fn -> Triggers.get_trigger_config!(trigger.id) end
    end

    test "list trigger configs" do
      t1 = trigger_config_fixture(%{name: "first"})
      t2 = trigger_config_fixture(%{name: "second"})
      configs = Triggers.list_trigger_configs()
      assert length(configs) == 2
      assert Enum.map(configs, & &1.id) == [t1.id, t2.id]
    end

    test "enabled defaults to true" do
      {:ok, config} = Triggers.create_trigger_config(%{name: "test"})
      assert config.enabled == true
    end

    test "can disable trigger config" do
      {:ok, config} = Triggers.create_trigger_config(%{name: "test", enabled: false})
      assert config.enabled == false
    end
  end

  describe "source config CRUD" do
    test "create an event source config" do
      trigger = trigger_config_fixture()

      assert {:ok, %TriggerSourceConfig{source_type: "event"}} =
               Triggers.create_source_config(%{
                 trigger_config_id: trigger.id,
                 source_type: "event",
                 config: %{"event_type" => "motion_detected"}
               })
    end

    test "validate source type" do
      trigger = trigger_config_fixture()

      {:error, changeset} =
        Triggers.create_source_config(%{
          trigger_config_id: trigger.id,
          source_type: "invalid",
          config: %{}
        })

      assert %{source_type: _} = errors_on(changeset)
    end

    test "event source requires event_type in config" do
      trigger = trigger_config_fixture()

      {:error, changeset} =
        Triggers.create_source_config(%{
          trigger_config_id: trigger.id,
          source_type: "event",
          config: %{}
        })

      assert %{config: _} = errors_on(changeset)
    end

    test "delete source config" do
      trigger = trigger_config_fixture()
      source = source_config_fixture(trigger)
      assert {:ok, _} = Triggers.delete_source_config(source)
    end
  end

  describe "target config CRUD" do
    test "create a log_message target" do
      trigger = trigger_config_fixture()

      assert {:ok, %TriggerTargetConfig{target_type: "log_message"}} =
               Triggers.create_target_config(%{
                 trigger_config_id: trigger.id,
                 target_type: "log_message",
                 config: %{"level" => "info", "message_prefix" => "Test"}
               })
    end

    test "create a device_control target" do
      trigger = trigger_config_fixture()

      assert {:ok, %TriggerTargetConfig{target_type: "device_control"}} =
               Triggers.create_target_config(%{
                 trigger_config_id: trigger.id,
                 target_type: "device_control",
                 config: %{"action" => "start"}
               })
    end

    test "validate target type" do
      trigger = trigger_config_fixture()

      {:error, changeset} =
        Triggers.create_target_config(%{
          trigger_config_id: trigger.id,
          target_type: "invalid"
        })

      assert %{target_type: _} = errors_on(changeset)
    end

    test "validate log_message level" do
      trigger = trigger_config_fixture()

      {:error, changeset} =
        Triggers.create_target_config(%{
          trigger_config_id: trigger.id,
          target_type: "log_message",
          config: %{"level" => "critical"}
        })

      assert %{config: _} = errors_on(changeset)
    end

    test "delete target config" do
      trigger = trigger_config_fixture()
      target = target_config_fixture(trigger)
      assert {:ok, _} = Triggers.delete_target_config(target)
    end
  end

  describe "device association" do
    test "associate trigger configs with a device", %{device: device} do
      t1 = trigger_config_fixture(%{name: "trigger_a"})
      t2 = trigger_config_fixture(%{name: "trigger_b"})

      assert :ok = Triggers.set_device_trigger_configs(device.id, [t1.id, t2.id])

      configs = Triggers.trigger_configs_for_device(device.id)
      assert length(configs) == 2
    end

    test "replacing device trigger configs", %{device: device} do
      t1 = trigger_config_fixture(%{name: "old"})
      t2 = trigger_config_fixture(%{name: "new"})

      Triggers.set_device_trigger_configs(device.id, [t1.id])
      Triggers.set_device_trigger_configs(device.id, [t2.id])

      configs = Triggers.trigger_configs_for_device(device.id)
      assert length(configs) == 1
      assert hd(configs).id == t2.id
    end

    test "disabled trigger configs are not returned", %{device: device} do
      trigger = trigger_config_fixture(%{enabled: false})
      Triggers.set_device_trigger_configs(device.id, [trigger.id])

      assert Triggers.trigger_configs_for_device(device.id) == []
    end

    test "deleting trigger config cascades to device associations", %{device: device} do
      trigger = trigger_config_fixture()
      Triggers.set_device_trigger_configs(device.id, [trigger.id])

      Triggers.delete_trigger_config(trigger)
      assert Triggers.trigger_configs_for_device(device.id) == []
    end
  end

  describe "matching_triggers/2" do
    test "finds matching triggers for device and event type", %{device: device} do
      full_trigger_fixture(device, %{event_type: "motion_detected"})

      triggers = Triggers.matching_triggers(device.id, "motion_detected")
      assert length(triggers) == 1
    end

    test "does not match different event type", %{device: device} do
      full_trigger_fixture(device, %{event_type: "motion_detected"})

      assert Triggers.matching_triggers(device.id, "door_open") == []
    end

    test "does not match disabled trigger config", %{device: device} do
      full_trigger_fixture(device, %{event_type: "motion_detected", enabled: false})

      assert Triggers.matching_triggers(device.id, "motion_detected") == []
    end

    test "does not match trigger for different device", %{device: device} do
      other_device = camera_device_fixture()
      full_trigger_fixture(other_device, %{event_type: "motion_detected"})

      assert Triggers.matching_triggers(device.id, "motion_detected") == []
    end

    test "returns multiple matching triggers", %{device: device} do
      t1 = trigger_config_fixture(%{name: "trigger_1"})
      source_config_fixture(t1, %{config: %{"event_type" => "motion_detected"}})
      target_config_fixture(t1)

      t2 = trigger_config_fixture(%{name: "trigger_2"})
      source_config_fixture(t2, %{config: %{"event_type" => "motion_detected"}})
      target_config_fixture(t2)

      Triggers.set_device_trigger_configs(device.id, [t1.id, t2.id])

      triggers = Triggers.matching_triggers(device.id, "motion_detected")
      assert length(triggers) == 2
    end
  end

  describe "cascade delete" do
    test "deleting trigger config deletes source and target configs" do
      trigger = trigger_config_fixture()
      _source = source_config_fixture(trigger)
      _target = target_config_fixture(trigger)

      {:ok, _} = Triggers.delete_trigger_config(trigger)

      assert Repo.all(TriggerSourceConfig) == []
      assert Repo.all(TriggerTargetConfig) == []
    end
  end
end
