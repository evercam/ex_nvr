defmodule ExNVR.Model.RemoteStorage do
  use Ecto.Schema

  alias Ecto.Changeset

  @type t :: %__MODULE__{
          type: :s3 | :seaweedfs,
          config: Config.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defmodule Config do
    use Ecto.Schema

    alias Ecto.Changeset

    @type t :: %__MODULE__{
            url: binary(),
            token: binary(),
            bucket: binary(),
            access_key_id: binary(),
            secret_access_key: binary(),
            region: binary()
          }

    @primary_key false
    embedded_schema do
      field :url, :string
      field :token, :string
      field :bucket, :string
      field :access_key_id, :string
      field :secret_access_key, :string
      field :region, :string
    end

    def changeset(struct, params, remote_storage_type) do
      struct
      |> Changeset.cast(params, [
        :url,
        :token,
        :bucket,
        :access_key_id,
        :secret_access_key,
        :region
      ])
      |> validate_config(remote_storage_type)
    end

    defp validate_config(changeset, :s3) do
      Changeset.validate_required(changeset, [
        :bucket,
        :access_key_id,
        :secret_access_key,
        :region
      ])
    end

    defp validate_config(changeset, :seaweedfs) do
      Changeset.validate_required(changeset, [:url, :token])
    end
  end

  schema "remote_storages" do
    field :name, :string
    field :type, Ecto.Enum, values: [:s3, :seaweedfs], default: :s3

    embeds_one :config, Config, on_replace: :update

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(remote_storage \\ %__MODULE__{}, params) do
    remote_storage
    |> Changeset.cast(params, [:name, :type])
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
