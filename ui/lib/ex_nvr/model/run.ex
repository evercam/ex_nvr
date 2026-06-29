defmodule ExNVR.Model.Run do
  @moduledoc """
  A run represent a recording session.

  An example of a run would be an RTSP session from start to finish. It's a helpful
  module to get the available footages
  """

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @seconds_in_day 86_400

  @type t :: %__MODULE__{
          start_date: DateTime.t() | nil,
          end_date: DateTime.t() | nil,
          active: boolean(),
          device_id: binary() | nil,
          disk_serial: String.t() | nil
        }

  @foreign_key_type :binary_id
  schema "runs" do
    field :start_date, :utc_datetime_usec
    field :end_date, :utc_datetime_usec
    field :active, :boolean, default: false
    field :stream, Ecto.Enum, values: [:high, :low], default: :high
    field :disk_serial, :string

    belongs_to :device, ExNVR.Model.Device
  end

  def deactivate_query(device_id) do
    from(r in __MODULE__, where: r.device_id == ^device_id and r.active == true)
  end

  def with_type(query \\ __MODULE__, stream_type) do
    where(query, [r], r.stream == ^stream_type)
  end

  def with_device(query \\ __MODULE__, device_id) do
    where(query, [r], r.device_id == ^device_id)
  end

  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {:device_id, id}, q -> where(q, [r], r.device_id == ^id)
      {:start_date, start_date}, q -> where(q, [r], r.end_date > ^start_date)
      _, q -> q
    end)
    |> order_by([r], asc: r.device_id, asc: r.start_date)
  end

  # get the summary of available footages grouped by device
  # and ignoring a provided gap between runs
  # e.g. a gap of 5 minutes (600 seconds) will combine any runs where the
  # diff between end_date of a run and start_date of the subsequent run
  # is less than the gap.
  def summary(gap_seconds) do
    gap = gap_seconds / @seconds_in_day
    fields = [:device_id, :disk_serial, :start_date, :end_date]

    __MODULE__
    |> where([r], r.stream == :high)
    |> select([r], map(r, ^fields))
    |> select_merge([r], %{
      prev_end_date:
        over(lag(r.end_date), partition_by: [r.device_id, r.disk_serial], order_by: r.start_date)
    })
    |> subquery()
    |> select([r], map(r, ^fields))
    |> select_merge([r], %{
      new_group:
        fragment(
          "case when ? is null or julianday(?) - julianday(?) > ? then 1 else 0 end",
          r.prev_end_date,
          r.start_date,
          r.prev_end_date,
          ^gap
        )
    })
    |> subquery()
    |> select([r], map(r, ^fields))
    |> select_merge([r], %{group_id: over(sum(r.new_group), :runs)})
    |> windows([r],
      runs: [
        partition_by: [r.device_id, r.disk_serial],
        order_by: r.start_date,
        frame: fragment("ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW")
      ]
    )
    |> subquery()
    |> select([r], %{
      device_id: r.device_id,
      disk_serial: r.disk_serial,
      start_date: min(r.start_date),
      end_date: max(r.end_date)
    })
    |> group_by([r], [r.device_id, r.disk_serial, r.group_id])
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    Changeset.cast(struct, params, __MODULE__.__schema__(:fields))
  end
end
