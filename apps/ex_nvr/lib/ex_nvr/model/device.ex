defmodule ExNVR.Model.Device do
  @moduledoc false

  use Ecto.Schema

  alias Ecto.Changeset

  @states [:stopped, :recording, :failed]

  @type t :: %__MODULE__{
          id: binary(),
          name: binary(),
          type: binary(),
          timezone: binary(),
          state: :stopped | :recording | :failed,
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
      |> Changeset.validate_change(:sub_stream_uri, &validate_uri/2)
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
    field :timezone, :string, default: "UTC"
    field :state, Ecto.Enum, values: @states, default: :recording

    embeds_one :ip_camera_config, IPCameraConfig, source: :config, on_replace: :update

    timestamps(type: :utc_datetime_usec)
  end

  def config_updated(%{type: :IP, ip_camera_config: config}, %{
        type: :IP,
        ip_camera_config: config
      }),
      do: false

  def config_updated(_device, _updated_device), do: true

  def has_sub_stream(%__MODULE__{ip_camera_config: nil}), do: false
  def has_sub_stream(%__MODULE__{ip_camera_config: %{sub_stream_uri: nil}}), do: false
  def has_sub_stream(_), do: true

  def create_changeset(device, params) do
    device
    |> Changeset.cast(params, [:name, :type, :timezone, :state])
    |> common_config()
  end

  def update_changeset(device, params) do
    device
    |> Changeset.cast(params, [:name, :timezone, :state])
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
    case Changeset.get_field(changeset, :type) do
      :IP ->
        Changeset.cast_embed(changeset, :ip_camera_config, required: true)

      _ ->
        changeset
    end
  end
end
