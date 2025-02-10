defmodule ExNVR.RemoteStorage do
  use Ecto.Schema

  alias Ecto.Changeset

  @type t :: %__MODULE__{
          type: :s3 | :http,
          s3_config: Config.t() | nil,
          http_config: Config.t() | nil,
          url: binary(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defmodule S3Config do
    use Ecto.Schema

    alias Ecto.Changeset

    @type t :: %__MODULE__{
            bucket: binary(),
            region: binary(),
            access_key_id: binary(),
            secret_access_key: binary()
          }

    @primary_key false
    embedded_schema do
      field :bucket, :string
      field :region, :string, default: "us-east-1"
      field :access_key_id, :string
      field :secret_access_key, :string
    end

    def changeset(struct, params) do
      struct
      |> Changeset.cast(params, __MODULE__.__schema__(:fields))
      |> Changeset.validate_required([
        :bucket,
        :access_key_id,
        :secret_access_key
      ])
    end
  end

  defmodule HttpConfig do
    use Ecto.Schema

    alias Ecto.Changeset

    @type t :: %__MODULE__{
            username: binary(),
            password: binary(),
            token: binary()
          }

    @primary_key false
    embedded_schema do
      field :username, :string
      field :password, :string
      field :token, :string
    end

    def changeset(struct, params) do
      struct
      |> Changeset.cast(params, __MODULE__.__schema__(:fields))
    end
  end

  schema "remote_storages" do
    field :name, :string
    field :type, Ecto.Enum, values: [:s3, :http]
    field :url, :string

    embeds_one :s3_config, S3Config, source: :config, on_replace: :update
    embeds_one :http_config, HttpConfig, source: :config, on_replace: :update

    timestamps(type: :utc_datetime_usec)
  end

  def build_opts(%{s3_config: s3_config, http_config: http_config} = remote_storage) do
    Map.merge(s3_config, http_config)
    |> Map.from_struct()
    |> Map.put(:url, remote_storage.url)
    |> add_auth_type()
    |> add_parsed_url()
    |> Map.to_list()
  end

  def create_changeset(remote_storage \\ %__MODULE__{}, params) do
    remote_storage
    |> Changeset.cast(params, [:name, :type, :url])
    |> Changeset.unique_constraint(:name)
    |> common_changeset()
  end

  def update_changeset(remote_storage, params) do
    remote_storage
    |> Changeset.cast(params, [:url])
    |> common_changeset()
  end

  defp common_changeset(changeset) do
    type = Changeset.get_field(changeset, :type)

    changeset
    |> validate_required(type)
    |> Changeset.validate_change(:url, &validate_url/2)
    |> validate_config(type)
  end

  defp validate_required(%Changeset{} = changeset, :s3) do
    Changeset.validate_required(changeset, [:name, :type])
  end

  defp validate_required(%Changeset{} = changeset, :http) do
    Changeset.validate_required(changeset, [:name, :type, :url])
  end

  defp validate_config(%Changeset{} = changeset, :s3) do
    Changeset.cast_embed(changeset, :s3_config,
      required: true,
      with: &S3Config.changeset(&1, &2)
    )
  end

  defp validate_config(%Changeset{} = changeset, :http) do
    Changeset.cast_embed(changeset, :http_config,
      required: true,
      with: &HttpConfig.changeset(&1, &2)
    )
  end

  defp validate_url(field, url) do
    parsed_url = URI.parse(url)

    cond do
      parsed_url.scheme not in ["http", "https"] ->
        [{field, "scheme should be http or https"}]

      to_string(parsed_url.host) == "" ->
        [{field, "invalid #{parsed_url.scheme} url"}]

      true ->
        []
    end
  end

  defp add_auth_type(%{type: :s3} = config), do: config

  defp add_auth_type(%{username: username, password: password, token: token} = config) do
    cond do
      not is_nil(token) ->
        Map.put(config, :auth_type, :bearer)

      not is_nil(username) && not is_nil(password) ->
        Map.put(config, :auth_type, :basic)

      true ->
        config
    end
  end

  defp add_parsed_url(%{type: :http} = config), do: config
  defp add_parsed_url(%{url: nil} = config), do: config

  defp add_parsed_url(config) do
    parsed_url_parts =
      config.url
      |> URI.parse()
      |> Map.take([:scheme, :host, :port])

    Map.merge(config, parsed_url_parts)
  end
end
