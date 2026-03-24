defmodule ExNVR.Triggers do
  @moduledoc """
  Context for managing trigger configurations.

  Triggers connect event sources (e.g., webhook events) to target actions
  (e.g., logging, starting/stopping recording).
  """

  import Ecto.Query

  alias ExNVR.Repo

  alias ExNVR.Triggers.{
    DeviceTriggerConfig,
    TriggerConfig,
    TriggerSourceConfig,
    TriggerSources,
    TriggerTargetConfig
  }

  @events_topic "events"
  @detections_topic "detections"

  def events_topic, do: @events_topic
  def detections_topic, do: @detections_topic

  # Trigger Config CRUD

  @spec create_trigger_config(map()) :: {:ok, TriggerConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_trigger_config(params) do
    %TriggerConfig{}
    |> TriggerConfig.changeset(params)
    |> Repo.insert()
  end

  @spec update_trigger_config(TriggerConfig.t(), map()) ::
          {:ok, TriggerConfig.t()} | {:error, Ecto.Changeset.t()}
  def update_trigger_config(%TriggerConfig{} = config, params) do
    config
    |> TriggerConfig.changeset(params)
    |> Repo.update()
  end

  @spec delete_trigger_config(TriggerConfig.t()) ::
          {:ok, TriggerConfig.t()} | {:error, Ecto.Changeset.t()}
  def delete_trigger_config(%TriggerConfig{} = config) do
    Repo.delete(config)
  end

  @spec get_trigger_config!(integer()) :: TriggerConfig.t()
  def get_trigger_config!(id) do
    TriggerConfig
    |> Repo.get!(id)
    |> Repo.preload([:source_configs, :target_configs, :devices])
  end

  @spec list_trigger_configs() :: [TriggerConfig.t()]
  def list_trigger_configs do
    TriggerConfig
    |> order_by([tc], tc.inserted_at)
    |> Repo.all()
    |> Repo.preload([:source_configs, :target_configs, :devices])
  end

  # Source Config CRUD

  @spec create_source_config(map()) ::
          {:ok, TriggerSourceConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_source_config(params) do
    %TriggerSourceConfig{}
    |> TriggerSourceConfig.changeset(params)
    |> Repo.insert()
  end

  @spec delete_source_config(TriggerSourceConfig.t()) ::
          {:ok, TriggerSourceConfig.t()} | {:error, Ecto.Changeset.t()}
  def delete_source_config(%TriggerSourceConfig{} = config) do
    Repo.delete(config)
  end

  # Target Config CRUD

  @spec create_target_config(map()) ::
          {:ok, TriggerTargetConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_target_config(params) do
    %TriggerTargetConfig{}
    |> TriggerTargetConfig.changeset(params)
    |> Repo.insert()
  end

  @spec delete_target_config(TriggerTargetConfig.t()) ::
          {:ok, TriggerTargetConfig.t()} | {:error, Ecto.Changeset.t()}
  def delete_target_config(%TriggerTargetConfig{} = config) do
    Repo.delete(config)
  end

  # Device association

  @spec set_device_trigger_configs(binary(), [integer()]) :: :ok
  def set_device_trigger_configs(device_id, trigger_config_ids) do
    # Delete existing associations
    from(dtc in DeviceTriggerConfig, where: dtc.device_id == ^device_id)
    |> Repo.delete_all()

    # Insert new associations
    Enum.each(trigger_config_ids, fn config_id ->
      %DeviceTriggerConfig{}
      |> Ecto.Changeset.change(%{device_id: device_id, trigger_config_id: config_id})
      |> Repo.insert!()
    end)

    :ok
  end

  @spec trigger_config_counts_by_device() :: %{binary() => non_neg_integer()}
  def trigger_config_counts_by_device do
    from(dtc in DeviceTriggerConfig,
      join: tc in TriggerConfig,
      on: tc.id == dtc.trigger_config_id,
      where: tc.enabled == true,
      group_by: dtc.device_id,
      select: {dtc.device_id, count(dtc.trigger_config_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @spec trigger_configs_for_device(binary()) :: [TriggerConfig.t()]
  def trigger_configs_for_device(device_id) do
    from(tc in TriggerConfig,
      join: dtc in DeviceTriggerConfig,
      on: dtc.trigger_config_id == tc.id,
      where: dtc.device_id == ^device_id and tc.enabled == true,
      preload: [:source_configs, :target_configs]
    )
    |> Repo.all()
  end

  @spec all_trigger_configs_for_device(binary()) :: [TriggerConfig.t()]
  def all_trigger_configs_for_device(device_id) do
    from(tc in TriggerConfig,
      join: dtc in DeviceTriggerConfig,
      on: dtc.trigger_config_id == tc.id,
      where: dtc.device_id == ^device_id,
      preload: [:source_configs, :target_configs]
    )
    |> Repo.all()
  end

  @doc """
  Returns all enabled trigger_recording target configs for a device.

  These are used by the pipeline to build one VideoBufferer + Storage branch
  per target config when recording_mode is :on_event.
  """
  @spec trigger_recording_configs_for_device(binary()) :: [TriggerTargetConfig.t()]
  def trigger_recording_configs_for_device(device_id) do
    from(ttc in TriggerTargetConfig,
      join: tc in TriggerConfig,
      on: ttc.trigger_config_id == tc.id,
      join: dtc in DeviceTriggerConfig,
      on: dtc.trigger_config_id == tc.id,
      where:
        dtc.device_id == ^device_id and
          tc.enabled == true and
          ttc.enabled == true and
          ttc.target_type == "trigger_recording"
    )
    |> Repo.all()
  end

  @doc """
  Find all enabled trigger configs for a device that match the given message.
  The raw PubSub message is passed to each source's `matches?/2` callback.
  """
  @spec matching_triggers(binary(), term()) :: [TriggerConfig.t()]
  def matching_triggers(device_id, message) do
    from(tc in TriggerConfig,
      join: dtc in DeviceTriggerConfig,
      on: dtc.trigger_config_id == tc.id,
      where: dtc.device_id == ^device_id,
      where: tc.enabled == true,
      preload: [:source_configs, :target_configs]
    )
    |> Repo.all()
    |> Enum.uniq_by(& &1.id)
    |> Enum.filter(fn tc ->
      Enum.any?(tc.source_configs, fn sc ->
        case TriggerSources.module_for(sc.source_type) do
          nil -> false
          module -> module.matches?(sc.config, message)
        end
      end)
    end)
  end
end
