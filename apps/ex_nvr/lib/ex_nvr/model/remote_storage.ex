defmodule ExNVR.Model.RemoteStorage do
  use Ecto.Schema

  alias Ecto.Changeset

  @type t :: %__MODULE__{
          type: :s3 | :http,
          config: Config.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defmodule Config do
    use Ecto.Schema

    alias Ecto.Changeset

    @type t :: %__MODULE__{
            url: binary(),
            username: binary(),
            password: binary(),
            token: binary(),
            bucket: binary(),
            access_key_id: binary(),
            secret_access_key: binary(),
            region: binary()
          }

    @primary_key false
    embedded_schema do
      field :url, :string
      field :username, :string
      field :password, :string
      field :token, :string
      field :bucket, :string
      field :access_key_id, :string
      field :secret_access_key, :string
      field :region, :string
    end

    def changeset(struct, params, :s3) do
      struct
      |> Changeset.cast(params, [
        :url,
        :bucket,
        :access_key_id,
        :secret_access_key,
        :region
      ])
      |> Changeset.validate_required([
        :bucket,
        :access_key_id,
        :secret_access_key,
        :region
      ])
      |> Changeset.validate_change(:url, fn :url, url -> validate_url(:url, url) end)
    end

    def changeset(struct, params, :http) do
      struct
      |> Changeset.cast(params, [
        :url,
        :username,
        :password,
        :token
      ])
      |> Changeset.validate_required([:url])
      |> Changeset.validate_change(:url, fn :url, url -> validate_url(:url, url) end)
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
  end

  schema "remote_storages" do
    field :name, :string
    field :type, Ecto.Enum, values: [:s3, :http], default: :s3

    embeds_one :config, Config, on_replace: :update

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(remote_storage \\ %__MODULE__{}, params) do
    remote_storage
    |> Changeset.cast(params, [:name, :type])
    |> Changeset.unique_constraint(:name)
    |> common_config()
  end

  def update_changeset(remote_storage, params) do
    remote_storage
    |> Changeset.cast(params, [])
    |> common_config()
  end

  defp common_config(changeset) do
    changeset
    |> Changeset.validate_required([:name, :type])
    |> validate_config()
  end

  defp validate_config(%Changeset{} = changeset) do
    type = Changeset.get_field(changeset, :type)

    Changeset.cast_embed(changeset, :config,
      required: true,
      with: &Config.changeset(&1, &2, type)
    )
  end
end
