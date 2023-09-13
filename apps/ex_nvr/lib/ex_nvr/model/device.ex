defmodule ExNVR.Model.Device do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @states [:stopped, :recording, :failed]

  @type state :: :stopped | :recording | :failed

  @type t :: %__MODULE__{
          id: binary(),
          name: binary(),
          type: binary(),
          timezone: binary(),
          state: state(),
          credentials: Credentials.t(),
          stream_config: StreamConfig.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

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

    def changeset(struct, params) do
      struct
      |> cast(params, __MODULE__.__schema__(:fields))
    end
  end

  defmodule StreamConfig do
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %__MODULE__{
            location: binary(),
            stream_uri: binary(),
            sub_stream_uri: binary()
          }

    @primary_key false
    embedded_schema do
      field :stream_uri, :string
      field :sub_stream_uri, :string
      field :location, :string
    end

    @file_extension_whitelist ~w(.mp4 .webm)

    def changeset(struct, params, type_of_device) do
      struct
      |> cast(params, [:stream_uri, :sub_stream_uri, :location])
      |> validate_device_config(type_of_device)
    end

    defp validate_device_config(changeset, type) do
      case type do
        :IP ->
          validate_required(changeset, [:stream_uri])
          |> Changeset.validate_change(:stream_uri, &validate_uri/2)
          |> Changeset.validate_change(:sub_stream_uri, &validate_uri/2)

        :FILE ->
          validate_required(changeset, [:location])
          |> Changeset.validate_change(:location, &validate_file_extension/2)
      end
    end

    defp validate_device_config(changeset, :file) do
      validate_required(changeset, [:location])
      |> Changeset.validate_change(:location, fn :location, location ->
        if File.exists?(location), do: [], else: [location: "File does not exist"]
      end)
      |> Changeset.validate_change(:location, fn :location, location ->
        Path.extname(location)
        |> String.downcase()
        |> Kernel.in(@file_extension_whitelist)
        |> case do
          true -> []
          false -> [location: "Invalid file extension"]
        end
      end)
    end

    defp validate_uri(field, rtsp_uri) do
      uri = URI.parse(rtsp_uri)

      cond do
        uri.scheme != "rtsp" ->
          [{field, "scheme should be rtsp"}]

        to_string(uri.host) == "" ->
          [{field, "invalid rtsp uri"}]

        true ->
          []
      end
    end

    defp validate_file_extension(field, file_location) do
      file_extension = get_ext(file_location)

      is_valid =
        @file_extension_whitelist
        |> Enum.member?(file_extension)

      if is_valid do
        []
      else
        [{field, "invalid File location"}]
      end
    end

    defp get_ext(file) do
      file
      |> Path.extname()
      |> String.downcase()
    end
  end

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "devices" do
    field :name, :string
    field :type, Ecto.Enum, values: [:IP, :FILE]
    field :timezone, :string, default: "UTC"
    field :state, Ecto.Enum, values: @states, default: :recording

    embeds_one :credentials, Credentials, source: :credentials, on_replace: :update
    embeds_one :stream_config, StreamConfig, source: :config, on_replace: :update

    timestamps(type: :utc_datetime_usec)
  end

  def streams(%__MODULE__{} = device), do: build_stream_uri(device)

  def config_updated(%{type: :IP, stream_config: config}, %{
        type: :IP,
        stream_config: config
      }),
      do: false

  def config_updated(_device, _updated_device), do: true

  def has_sub_stream(%__MODULE__{stream_config: nil}), do: false
  def has_sub_stream(%__MODULE__{stream_config: %StreamConfig{sub_stream_uri: nil}}), do: false
  def has_sub_stream(_), do: true

  def recording?(%__MODULE__{state: :stopped}), do: false
  def recording?(_), do: true

  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {:state, value}, q when is_atom(value) -> where(q, [d], d.state == ^value)
      {:state, values}, q when is_list(values) -> where(q, [d], d.state in ^values)
      _, q -> q
    end)
  end

  def create_changeset(device, params) do
    device
    |> Changeset.cast(params, [:name, :type, :timezone, :state])
    |> Changeset.cast_embed(:credentials)
    |> common_config()
  end

  def update_changeset(device, params) do
    device
    |> Changeset.cast(params, [:name, :timezone, :state])
    |> Changeset.cast_embed(:credentials)
    |> common_config()
  end

  defp common_config(changeset) do
    changeset
    |> Changeset.validate_required([:name, :type])
    |> Changeset.validate_inclusion(:timezone, Tzdata.zone_list())
    |> validate_config()
  end

  defp validate_config(%Changeset{valid?: false} = cs), do: cs

  defp validate_config(%Changeset{} = changeset) do
    type = Changeset.get_field(changeset, :type)

    case type do
      :IP ->
        Changeset.cast_embed(changeset, :credentials)
        |> Changeset.cast_embed(:stream_config,
          required: true,
          with: fn struct, params -> StreamConfig.changeset(struct, params, :IP) end
        )

      :FILE ->
        Changeset.cast_embed(changeset, :stream_config,
          required: true,
          with: fn struct, params -> StreamConfig.changeset(struct, params, :FILE) end
        )

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
