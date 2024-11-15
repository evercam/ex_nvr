defmodule ExNVR.Model.Device do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset
  alias ExNVR.Model.Device.{SnapshotConfig, StorageConfig}

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
            enable_lpr: boolean()
          }

    @primary_key false
    embedded_schema do
      field :generate_bif, :boolean, default: true
      field :enable_lpr, :boolean, default: false
    end

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(struct, params) do
      cast(struct, params, __MODULE__.__schema__(:fields))
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
    embeds_one :storage_config, StorageConfig, on_replace: :update
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

  @spec http_url(t()) :: binary() | nil
  def http_url(%__MODULE__{url: nil}), do: nil

  def http_url(%__MODULE__{url: url}) do
    url
    |> URI.parse()
    |> Map.put(:path, nil)
    |> URI.to_string()
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
      device_1.storage_config != device_2.storage_config
  end

  @spec has_sub_stream(t()) :: boolean()
  def has_sub_stream(%__MODULE__{stream_config: nil}), do: false
  def has_sub_stream(%__MODULE__{stream_config: %StreamConfig{sub_stream_uri: nil}}), do: false
  def has_sub_stream(_), do: true

  @spec recording?(t()) :: boolean()
  def recording?(%__MODULE__{state: state}), do: state != :stopped

  # directories path

  @spec base_dir(t()) :: Path.t()
  def base_dir(%__MODULE__{id: id, storage_config: %{address: path}}),
    do: Path.join([path, "ex_nvr", id])

  @spec recording_dir(t()) :: Path.t()
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

  @spec snapshot_config(t()) :: map()
  def snapshot_config(%{snapshot_config: nil}) do
    %{enabled: false}
  end

  def snapshot_config(%{snapshot_config: snapshot_config}) do
    config = Map.take(snapshot_config, [:enabled, :remote_storage, :upload_interval])

    if config.enabled do
      {:ok, schedule} = SnapshotConfig.parse_schedule(snapshot_config.schedule)
      Map.put(snapshot_config, :schedule, schedule)
    else
      config
    end
  end

  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {:state, value}, q when is_atom(value) -> where(q, [d], d.state == ^value)
      {:state, values}, q when is_list(values) -> where(q, [d], d.state in ^values)
      {:type, value}, q -> where(q, [d], d.type == ^value)
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
    |> Changeset.cast_embed(:storage_config, required: true)
    |> common_config()
  end

  def update_changeset(device, params) do
    device
    |> Changeset.cast(params, [:name, :timezone, :state, :vendor, :mac, :url, :model])
    |> Changeset.cast_embed(:credentials)
    |> Changeset.cast_embed(:storage_config,
      required: true,
      with: &StorageConfig.update_changeset/2
    )
    |> common_config()
  end

  defp common_config(changeset) do
    changeset
    |> Changeset.validate_required([:name, :type])
    |> Changeset.validate_inclusion(:timezone, Tzdata.zone_list())
    |> Changeset.cast_embed(:settings)
    |> Changeset.cast_embed(:snapshot_config)
    |> validate_config()
    |> maybe_set_default_settings()
  end

  defp validate_config(%Changeset{} = changeset) do
    type = Changeset.get_field(changeset, :type)

    Changeset.cast_embed(changeset, :stream_config,
      required: true,
      with: &StreamConfig.changeset(&1, &2, type)
    )
  end

  defp maybe_set_default_settings(changeset) do
    if Changeset.get_field(changeset, :settings),
      do: changeset,
      else: Changeset.put_embed(changeset, :settings, %Settings{})
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
