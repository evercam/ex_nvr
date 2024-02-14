defmodule ExNVR.Model.Device do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @states [:stopped, :recording, :failed]
  @camera_vendors ["HIKVISION", "Milesight Technology Co.,Ltd.", "AXIS"]

  @type state :: :stopped | :recording | :failed
  @type id :: binary()

  @type t :: %__MODULE__{}

  defmodule Credentials do
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %__MODULE__{
            username: binary(),
            password: binary()
          }

    @primary_key false
    embedded_schema do
      field :username, :string
      field :password, :string
    end

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(struct, params) do
      struct
      |> cast(params, __MODULE__.__schema__(:fields))
    end
  end

  defmodule StreamConfig do
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %__MODULE__{
            filename: binary(),
            temporary_path: Path.t(),
            duration: Membrane.Time.t(),
            stream_uri: binary(),
            sub_stream_uri: binary(),
            snapshot_uri: binary()
          }

    @primary_key false
    embedded_schema do
      field :stream_uri, :string
      field :sub_stream_uri, :string
      field :snapshot_uri, :string
      field :filename, :string
      field :temporary_path, :string, virtual: true
      field :duration, :integer
    end

    def changeset(struct, params, device_type) do
      struct
      |> cast(params, [
        :stream_uri,
        :sub_stream_uri,
        :snapshot_uri,
        :filename,
        :temporary_path,
        :duration
      ])
      |> validate_device_config(device_type)
    end

    defp validate_device_config(changeset, :ip) do
      validate_required(changeset, [:stream_uri])
      |> Changeset.validate_change(:stream_uri, &validate_uri/2)
      |> Changeset.validate_change(:sub_stream_uri, &validate_uri/2)
      |> Changeset.validate_change(:snapshot_uri, fn :snapshot_uri, snapshot_uri ->
        validate_uri(:snapshot_uri, snapshot_uri, "http")
      end)
    end

    defp validate_device_config(changeset, :file) do
      validate_required(changeset, [:filename, :duration])
    end

    defp validate_uri(field, uri, protocl \\ "rtsp") do
      parsed_uri = URI.parse(uri)

      cond do
        parsed_uri.scheme != protocl ->
          [{field, "scheme should be #{protocl}"}]

        to_string(parsed_uri.host) == "" ->
          [{field, "invalid #{protocl} uri"}]

        true ->
          []
      end
    end
  end

  defmodule Settings do
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %__MODULE__{
            generate_bif: boolean(),
            storage_address: binary()
          }

    @primary_key false
    embedded_schema do
      field :generate_bif, :boolean, default: true
      field :storage_address, :string
      field :override_on_full_disk, :boolean, default: false
      field :override_on_full_disk_threshold, :float, default: 95.0
    end

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(struct, params) do
      struct
      |> cast(params, __MODULE__.__schema__(:fields))
      |> validate_required([:storage_address])
      |> validate_number(:override_on_full_disk_threshold,
        less_than_or_equal_to: 100,
        greater_than_or_equal_to: 0,
        message: "value must be between 0 and 100"
      )
      |> validate_change(:storage_address, fn :storage_address, mountpoint ->
        case File.stat(mountpoint) do
          {:ok, %File.Stat{access: :read_write}} -> []
          _other -> [storage_address: "has no write permissions"]
        end
      end)
    end

    @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
    def update_changeset(struct, params) do
      struct
      |> cast(params, [:generate_bif, :override_on_full_disk, :override_on_full_disk_threshold])
      |> validate_number(:override_on_full_disk_threshold,
        less_than_or_equal_to: 100,
        greater_than_or_equal_to: 0,
        message: "value must be between 0 and 100"
      )
      |> validate_required([:storage_address])
    end
  end

  defmodule SnapshotConfig do
    use Ecto.Schema

    import Ecto.Changeset

    @time_interval_regex ~r/^([01]\d|2[0-3]):([0-5]\d)-([01]\d|2[0-3]):([0-5]\d)$/
    @days_of_week ~w(1 2 3 4 5 6 7)

    @type t :: %__MODULE__{
            enabled: boolean(),
            upload_interval: integer(),
            remote_storage: binary(),
            schedule: list()
          }

    @primary_key false
    embedded_schema do
      field :enabled, :boolean
      field :upload_interval, :integer
      field :remote_storage, :string
      field :schedule, :map
    end

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(struct, params) do
      changeset =
        struct
        |> cast(params, [:enabled, :upload_interval, :remote_storage, :schedule])

      enabled = get_field(changeset, :enabled)
      validate_config(changeset, enabled)
    end

    defp validate_config(changeset, true) do
      changeset
      |> validate_required([:enabled, :upload_interval, :remote_storage, :schedule])
      |> validate_number(:upload_interval,
        greater_than_or_equal_to: 5,
        less_than_or_equal_to: 3600
      )
      |> validate_schedule()
    end

    defp validate_config(changeset, _enabled) do
      changeset
      |> put_change(:upload_interval, 0)
      |> put_change(:remote_storage, nil)
      |> put_change(:schedule, %{})
    end

    defp validate_schedule(%Changeset{valid?: false} = changeset), do: changeset

    defp validate_schedule(changeset) do
      changeset
      |> get_field(:schedule)
      |> do_validate_schedule()
      |> case do
        {:ok, schedule} ->
          put_change(changeset, :schedule, schedule)

        {:error, :invalid_schedule_days} ->
          add_error(changeset, :schedule, "Invalid schedule days")

        {:error, :invalid_time_intervals} ->
          add_error(changeset, :schedule, "Invalid schedule time intervals format")

        {:error, :invalid_time_interval_range} ->
          add_error(
            changeset,
            :schedule,
            "Invalid schedule time intervals range (start time must be before end time)"
          )

        {:error, :overlapping_intervals} ->
          add_error(changeset, :schedule, "Schedule time intervals must not overlap")
      end
    end

    defp do_validate_schedule(schedule) do
      schedule =
        schedule
        |> Enum.into(%{
          "1" => [],
          "2" => [],
          "3" => [],
          "4" => [],
          "5" => [],
          "6" => [],
          "7" => []
        })

      with {:ok, schedule} <- validate_schedule_days(schedule),
           {:ok, parsed_schedule} <- parse_schedule(schedule),
           {:ok, _parsed_schedule} <- validate_schedule_intervals(parsed_schedule) do
        schedule
        |> Enum.map(fn {day, intervals} -> {day, Enum.sort(intervals)} end)
        |> Map.new()
        |> then(&{:ok, &1})
      end
    end

    defp validate_schedule_days(schedule) do
      schedule
      |> Map.keys()
      |> Enum.all?(&Enum.member?(@days_of_week, &1))
      |> case do
        true -> {:ok, schedule}
        false -> {:error, :invalid_schedule_days}
      end
    end

    defp parse_schedule(schedule) do
      schedule
      |> Enum.reduce_while(%{}, fn {day_of_week, time_intervals}, acc ->
        case parse_day_schedule(time_intervals) do
          :invalid_time_intervals ->
            {:halt, :invalid_time_intervals}

          parsed_time_intervals ->
            {:cont, Map.put(acc, day_of_week, parsed_time_intervals)}
        end
      end)
      |> case do
        :invalid_time_intervals ->
          {:error, :invalid_time_intervals}

        parsed_schedule ->
          {:ok, parsed_schedule}
      end
    end

    defp parse_day_schedule(time_intervals) when is_list(time_intervals) do
      Enum.reduce_while(time_intervals, [], fn time_interval, acc ->
        case Regex.match?(@time_interval_regex, time_interval) do
          false ->
            {:halt, :invalid_time_intervals}

          true ->
            [start_time, end_time] = String.split(time_interval, "-")

            {:cont,
             acc ++
               [
                 %{
                   start_time: Time.from_iso8601!(start_time <> ":00"),
                   end_time: Time.from_iso8601!(end_time <> ":00")
                 }
               ]}
        end
      end)
    end

    defp parse_day_schedule(_time_intervals), do: :invalid_time_intervals

    defp validate_schedule_intervals(schedule) do
      Enum.reduce_while(schedule, :ok, fn {_day_of_week, time_intervals}, _acc ->
        sorted_intervals =
          Enum.sort(time_intervals, &(Time.compare(&1.start_time, &2.start_time) == :lt))

        with true <- Enum.all?(sorted_intervals, &valid_time_interval?/1),
             :ok <- no_overlapping_intervals(sorted_intervals) do
          {:cont, :ok}
        else
          false -> {:halt, :invalid_time_interval_range}
          :overlapping_intervals -> {:halt, :overlapping_intervals}
        end
      end)
      |> case do
        :ok -> {:ok, schedule}
        error -> {:error, error}
      end
    end

    defp valid_time_interval?(%{start_time: start_time, end_time: end_time}) do
      Time.compare(end_time, start_time) == :gt
    end

    defp no_overlapping_intervals(intervals) do
      intervals
      |> Enum.reduce_while(nil, &check_overlap/2)
      |> case do
        :overlapping_intervals ->
          :overlapping_intervals

        _end_time ->
          :ok
      end
    end

    defp check_overlap(%{start_time: start_time, end_time: end_time}, prev_end_time) do
      cond do
        is_nil(prev_end_time) -> {:cont, end_time}
        Time.compare(start_time, prev_end_time) in [:gt, :eq] -> {:cont, end_time}
        true -> {:halt, :overlapping_intervals}
      end
    end
  end

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "devices" do
    field :name, :string
    field :type, Ecto.Enum, values: [:ip, :file], default: :ip
    field :timezone, :string, default: "UTC"
    field :state, Ecto.Enum, values: @states, default: :recording
    field :vendor, :string
    field :mac, :string
    field :url, :string
    field :model, :string

    embeds_one :credentials, Credentials, source: :credentials, on_replace: :update
    embeds_one :stream_config, StreamConfig, source: :config, on_replace: :update
    embeds_one :settings, Settings, on_replace: :update
    embeds_one :snapshot_config, SnapshotConfig, on_replace: :update

    timestamps(type: :utc_datetime_usec)
  end

  @spec vendors() :: [binary()]
  def vendors(), do: @camera_vendors

  @spec vendor(t()) :: atom()
  def vendor(%__MODULE__{vendor: vendor}) do
    case vendor do
      "HIKVISION" -> :hik
      "Milesight Technology Co.,Ltd." -> :milesight
      "AXIS" -> :axis
      _other -> :unknown
    end
  end

  @spec streams(t()) :: {binary(), binary() | nil}
  def streams(%__MODULE__{} = device), do: build_stream_uri(device)

  @spec file_location(t()) :: Path.t()
  def file_location(%__MODULE__{stream_config: %{filename: filename}} = device) do
    Path.join(base_dir(device), filename)
  end

  @spec file_duration(t()) :: Membrane.Time.t()
  def file_duration(%__MODULE__{type: :file, stream_config: %{duration: duration}}), do: duration

  @spec config_updated(t(), t()) :: boolean()
  def config_updated(%__MODULE__{} = device_1, %__MODULE__{} = device_2) do
    device_1.stream_config != device_2.stream_config or device_1.settings != device_2.settings or
      device_1.snapshot_config != device_2.snapshot_config
  end

  @spec has_sub_stream(t()) :: boolean()
  def has_sub_stream(%__MODULE__{stream_config: nil}), do: false
  def has_sub_stream(%__MODULE__{stream_config: %StreamConfig{sub_stream_uri: nil}}), do: false
  def has_sub_stream(_), do: true

  @spec recording?(t()) :: boolean()
  def recording?(%__MODULE__{state: state}), do: state != :stopped

  # directories path

  @spec base_dir(t()) :: Path.t()
  def base_dir(%__MODULE__{id: id, settings: %{storage_address: path}}),
    do: Path.join([path, "ex_nvr", id])

  @spec recording_dir(t(), :high | :low) :: Path.t()
  def recording_dir(%__MODULE__{} = device, stream \\ :high) do
    stream = if stream == :high, do: "hi_quality", else: "lo_quality"
    Path.join(base_dir(device), stream)
  end

  @spec bif_dir(t()) :: Path.t()
  def bif_dir(%__MODULE__{} = device) do
    Path.join(base_dir(device), "bif")
  end

  @spec bif_thumbnails_dir(t()) :: Path.t()
  def bif_thumbnails_dir(%__MODULE__{} = device) do
    Path.join([base_dir(device), "thumbnails", "bif"])
  end

  @spec thumbnails_dir(t()) :: Path.t()
  def thumbnails_dir(%__MODULE__{} = device) do
    Path.join([base_dir(device), "thumbnails"])
  end

  @spec lpr_thumbnails_dir(t()) :: Path.t()
  def lpr_thumbnails_dir(device) do
    Path.join(thumbnails_dir(device), "lpr")
  end

  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {:state, value}, q when is_atom(value) -> where(q, [d], d.state == ^value)
      {:state, values}, q when is_list(values) -> where(q, [d], d.state in ^values)
      _, q -> q
    end)
  end

  @spec states() :: [state()]
  def states(), do: @states

  # Changesets
  def create_changeset(device \\ %__MODULE__{}, params) do
    device
    |> Changeset.cast(params, [:name, :type, :timezone, :state, :vendor, :mac, :url, :model])
    |> Changeset.cast_embed(:credentials)
    |> Changeset.cast_embed(:settings, required: true)
    |> Changeset.cast_embed(:snapshot_config)
    |> common_config()
  end

  def update_changeset(device, params) do
    device
    |> Changeset.cast(params, [:name, :timezone, :state, :vendor, :mac, :url, :model])
    |> Changeset.cast_embed(:credentials)
    |> Changeset.cast_embed(:settings, required: true, with: &Settings.update_changeset/2)
    |> Changeset.cast_embed(:snapshot_config)
    |> common_config()
  end

  defp common_config(changeset) do
    changeset
    |> Changeset.validate_required([:name, :type])
    |> Changeset.validate_inclusion(:timezone, Tzdata.zone_list())
    |> validate_config()
  end

  defp validate_config(%Changeset{} = changeset) do
    type = Changeset.get_field(changeset, :type)

    Changeset.cast_embed(changeset, :stream_config,
      required: true,
      with: &StreamConfig.changeset(&1, &2, type)
    )
  end

  defp build_stream_uri(%__MODULE__{stream_config: config, credentials: credentials_config}) do
    userinfo =
      if to_string(credentials_config.username) != "" and
           to_string(credentials_config.password) != "" do
        "#{credentials_config.username}:#{credentials_config.password}"
      end

    {do_build_uri(config.stream_uri, userinfo), do_build_uri(config.sub_stream_uri, userinfo)}
  end

  defp build_stream_uri(_), do: nil

  defp do_build_uri(nil, _userinfo), do: nil

  defp do_build_uri(stream_uri, userinfo) do
    stream_uri
    |> URI.parse()
    |> then(&%URI{&1 | userinfo: userinfo})
    |> URI.to_string()
  end
end
