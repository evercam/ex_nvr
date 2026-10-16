defmodule ExNVR.Activity do
  @moduledoc """
  Activity log: the actions made by users, API clients and the remote server
  (logins, configuration changes, exports, ...).

  What the system does on its own (power, reboots, camera streams, ...) is not
  activity, it's stored as events, see `ExNVR.Events`.

  Entries are written asynchronously in batches by `ExNVR.Activity.Writer`,
  every entry needs an actor:

      ExNVR.Activity.log(
        category: :device,
        action: "device.updated",
        message: "Device Front Gate updated",
        actor: Actor.user(user, ip: ip),
        device: device,
        resource: %{type: "device", id: device.id, label: device.name},
        metadata: %{changes: Diff.changes(old_device, device)}
      )

  When the `:activity_sync_writes` config is set (tests), entries are inserted
  directly in the calling process.
  """

  import Ecto.Query

  require Logger

  alias Ecto.Changeset
  alias ExNVR.Activity.{Actor, Entry, Writer}
  alias ExNVR.Repo

  @topic "activity"

  @type flop_result :: {:ok, {[Entry.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}

  @type attrs :: %{
          required(:category) => atom(),
          required(:action) => String.t(),
          required(:message) => String.t(),
          required(:actor) => Actor.t(),
          optional(:severity) => :info | :warning | :critical,
          optional(:device) => map() | nil,
          optional(:resource) => %{type: String.t(), id: term(), label: String.t()} | nil,
          optional(:metadata) => map(),
          optional(:time) => DateTime.t()
        }

  @doc """
  Logs an activity entry asynchronously.

  Never blocks on the database. Returns `{:error, changeset}` only when the
  attributes are invalid.
  """
  @spec log(attrs() | Keyword.t()) :: :ok | {:error, Changeset.t()}
  def log(attrs) do
    with {:ok, entry} <- build(attrs) do
      if sync_writes?(), do: insert_entries([entry]), else: Writer.write(entry)
      :ok
    end
  end

  @doc """
  Logs an activity entry and waits until it's persisted.
  """
  @spec log_sync(attrs() | Keyword.t()) :: :ok | {:error, term()}
  def log_sync(attrs) do
    with {:ok, entry} <- build(attrs) do
      if sync_writes?(), do: insert_entries([entry]), else: Writer.write_sync(entry)
    end
  catch
    :exit, reason ->
      Logger.error("[Activity] failed to write entry synchronously: #{inspect(reason)}")
      {:error, reason}
  end

  @spec list(map(), Keyword.t()) :: flop_result()
  def list(params, opts \\ []) do
    Entry
    |> filter_device(opts[:device_id])
    |> ExNVR.Flop.validate_and_run(params, for: Entry)
  end

  @spec get(integer()) :: Entry.t() | nil
  def get(id), do: Repo.get(Entry, id)

  @doc """
  Subscribes the caller to new entries.

  Receives `{:activity_logged, [Entry.t()]}` messages, entries are not guaranteed
  to have an `id` yet.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(ExNVR.PubSub, @topic)

  @spec delete_older_than(pos_integer()) :: non_neg_integer()
  def delete_older_than(days) do
    limit = DateTime.add(DateTime.utc_now(), -days, :day)
    {count, _} = Repo.delete_all(where(Entry, [e], e.time < ^limit))
    count
  end

  @doc false
  @spec build(attrs() | Keyword.t()) :: {:ok, Entry.t()} | {:error, Changeset.t()}
  def build(attrs) do
    attrs = Map.new(attrs)

    params =
      %{
        time: attrs[:time] || DateTime.utc_now(),
        category: attrs[:category],
        action: attrs[:action],
        severity: attrs[:severity] || :info,
        message: attrs[:message],
        metadata: encodable_metadata(attrs[:metadata] || %{})
      }
      |> Map.merge(actor_fields(attrs[:actor]))
      |> Map.merge(device_fields(attrs[:device]))
      |> Map.merge(resource_fields(attrs[:resource]))

    case Entry.changeset(params) do
      %Changeset{valid?: true} = changeset ->
        {:ok, Changeset.apply_changes(changeset)}

      changeset ->
        Logger.warning(
          "[Activity] invalid entry #{inspect(attrs[:action])}, " <>
            "invalid fields: #{inspect(Keyword.keys(changeset.errors))}"
        )

        {:error, changeset}
    end
  end

  @doc false
  @spec insert_entries([Entry.t()]) :: :ok | {:error, term()}
  def insert_entries(entries) do
    rows = Enum.map(entries, &(&1 |> Map.from_struct() |> Map.drop([:__meta__, :id])))
    Repo.insert_all(Entry, rows)
    Phoenix.PubSub.broadcast(ExNVR.PubSub, @topic, {:activity_logged, entries})
    :ok
  rescue
    error -> {:error, error}
  end

  defp filter_device(query, nil), do: query
  defp filter_device(query, device_id), do: where(query, [e], e.device_id == ^device_id)

  defp actor_fields(%Actor{} = actor) do
    %{actor_type: actor.type, actor_id: actor.id, actor_label: actor.label, source_ip: actor.ip}
  end

  defp actor_fields(_no_actor), do: %{}

  defp device_fields(nil), do: %{}
  defp device_fields(device), do: %{device_id: device.id, device_name: device.name}

  defp resource_fields(nil), do: %{}

  defp resource_fields(resource) do
    %{
      resource_type: to_string(resource.type),
      resource_id: resource[:id] && to_string(resource.id),
      resource_label: resource[:label]
    }
  end

  # A batch insert fails as a whole, make sure one bad metadata map can't lose other entries.
  defp encodable_metadata(metadata) do
    case Jason.encode(metadata) do
      {:ok, _json} -> metadata
      {:error, _reason} -> %{"raw" => inspect(metadata, limit: 50, printable_limit: 1_000)}
    end
  end

  defp sync_writes?, do: Application.get_env(:ex_nvr, :activity_sync_writes, false)
end
