defmodule ExNVR.Model.Device do
  @moduledoc false

  use Ecto.Schema

  alias Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          name: binary(),
          type: binary(),
          config: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "devices" do
    field :name, :string
    field :type, Ecto.Enum, values: [:IP]
    field :config, :map

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> Changeset.cast(params, [:name, :type, :config])
    |> Changeset.validate_required([:name, :type])
    |> validate_config()
  end

  defp validate_config(%Changeset{valid?: false} = cs), do: cs

  defp validate_config(%Changeset{} = changeset) do
    type = Changeset.get_field(changeset, :type)
    config = Changeset.get_field(changeset, :config)

    case validate_camera_config(type, config) do
      {:ok, config} ->
        Changeset.put_change(changeset, :config, config)

      {:error, changeset} ->
        Changeset.add_error(changeset, :config, "invalid config")
    end
  end

  defp validate_camera_config(:ip, config) do
    types = %{
      stream_uri: :string,
      username: :string,
      password: :string
    }

    {%{}, types}
    |> Changeset.cast(config, Map.keys(types))
    |> Changeset.validate_required([:stream_uri])
    |> Changeset.validate_change(:stream_uri, fn :stream_uri, rtsp_uri ->
      uri = URI.parse(rtsp_uri)

      cond do
        uri.scheme != "rtsp" ->
          [stream_uri: "schame should be rtsp"]

        is_nil(uri.host) ->
          [stream_uri: "invalid rtsp uri"]

        true ->
          []
      end
    end)
    |> Changeset.apply_action(:create)
  end
end
