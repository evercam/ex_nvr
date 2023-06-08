defmodule ExNVR.Model.Device do
  @moduledoc false

  use Ecto.Schema

  alias Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          name: binary(),
          type: binary(),
          ip_camera_config: IPCameraConfig.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defmodule IPCameraConfig do
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %__MODULE__{
            stream_uri: binary(),
            username: binary(),
            password: binary()
          }

    @primary_key false
    embedded_schema do
      field :stream_uri, :string
      field :sub_stream_uri, :string
      field :username, :string
      field :password, :string
    end

    def changeset(struct, params) do
      struct
      |> cast(params, __MODULE__.__schema__(:fields))
      |> validate_required([:stream_uri])
      |> Changeset.validate_change(:stream_uri, &validate_uri/2)
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
  end

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "devices" do
    field :name, :string
    field :type, Ecto.Enum, values: [:IP]

    embeds_one :ip_camera_config, IPCameraConfig, source: :config, on_replace: :update

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> Changeset.cast(params, [:name, :type])
    |> Changeset.validate_required([:name, :type])
    |> validate_config()
  end

  defp validate_config(%Changeset{valid?: false} = cs), do: cs

  defp validate_config(%Changeset{} = changeset) do
    case Changeset.get_field(changeset, :type) do
      :IP ->
        Changeset.cast_embed(changeset, :ip_camera_config, required: true)

      _ ->
        changeset
    end
  end
end
