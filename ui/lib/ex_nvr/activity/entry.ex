defmodule ExNVR.Activity.Entry do
  @moduledoc """
  A single activity log entry: an action made by a user, an API client or the
  remote server. What the system does on its own is stored as events.

  `device_id` and `actor_id` are not foreign keys, entries are kept after the
  referenced device or user is deleted. `device_name`, `actor_label` and
  `resource_label` are snapshots taken when the entry was logged.
  """

  use Ecto.Schema

  alias Ecto.Changeset

  @categories [:auth, :user, :device, :export, :config, :remote]
  @severities [:info, :warning, :critical]
  @actor_types [:user, :api, :remote]

  @derive {Flop.Schema,
           filterable: [
             :time,
             :category,
             :action,
             :severity,
             :actor_type,
             :actor_id,
             :device_id,
             :message
           ],
           sortable: [:time, :category, :severity, :id],
           default_order: %{
             order_by: [:time, :id],
             order_directions: [:desc, :desc]
           },
           pagination_types: [:page],
           default_limit: 50,
           max_limit: 200}

  @derive {Jason.Encoder, except: [:__meta__]}

  @type t :: %__MODULE__{}

  schema "activity_logs" do
    field :time, :utc_datetime_usec
    field :category, Ecto.Enum, values: @categories
    field :action, :string
    field :severity, Ecto.Enum, values: @severities, default: :info
    field :actor_type, Ecto.Enum, values: @actor_types
    field :actor_id, :string
    field :actor_label, :string
    field :device_id, :binary_id
    field :device_name, :string
    field :resource_type, :string
    field :resource_id, :string
    field :resource_label, :string
    field :message, :string
    field :metadata, :map, default: %{}
    field :source_ip, :string
  end

  @fields [
    :time,
    :category,
    :action,
    :severity,
    :actor_type,
    :actor_id,
    :actor_label,
    :device_id,
    :device_name,
    :resource_type,
    :resource_id,
    :resource_label,
    :message,
    :metadata,
    :source_ip
  ]

  @spec categories() :: [atom()]
  def categories, do: @categories

  @spec severities() :: [atom()]
  def severities, do: @severities

  def changeset(entry \\ %__MODULE__{}, params) do
    entry
    |> Changeset.cast(params, @fields)
    |> Changeset.validate_required([:time, :category, :action, :severity, :actor_type, :message])
  end
end
