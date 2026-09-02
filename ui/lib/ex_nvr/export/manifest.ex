defmodule ExNVR.Export.Manifest do
  @moduledoc "On-disk state of an export job, stored at dest_dir/.export_manifest.json."

  @manifest_filename ".export_manifest.json"
  @schema_version 1

  @type status :: :running | :paused | :completed | :failed

  @type file_entry :: %{
          filename: String.t(),
          start_date: DateTime.t(),
          end_date: DateTime.t(),
          size: non_neg_integer()
        }

  @type t :: %__MODULE__{
          version: pos_integer(),
          device_id: binary(),
          stream: :high | :low,
          start_date: DateTime.t(),
          end_date: DateTime.t(),
          max_duration: pos_integer() | nil,
          max_file_size: pos_integer() | nil,
          cursor: DateTime.t(),
          status: status(),
          error: String.t() | nil,
          files: [file_entry()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @derive Jason.Encoder
  @enforce_keys [:device_id, :stream, :start_date, :end_date, :cursor]
  defstruct version: @schema_version,
            device_id: nil,
            stream: nil,
            start_date: nil,
            end_date: nil,
            max_duration: nil,
            max_file_size: nil,
            cursor: nil,
            status: :running,
            error: nil,
            files: [],
            inserted_at: nil,
            updated_at: nil

  @spec manifest_path(Path.t()) :: Path.t()
  def manifest_path(dest_dir), do: Path.join(dest_dir, @manifest_filename)

  @spec new(map()) :: t()
  def new(params) do
    now = DateTime.utc_now()

    struct!(__MODULE__, %{
      device_id: Map.fetch!(params, :device_id),
      stream: Map.fetch!(params, :stream),
      start_date: Map.fetch!(params, :start_date),
      end_date: Map.fetch!(params, :end_date),
      max_duration: params[:max_duration],
      max_file_size: params[:max_file_size],
      cursor: Map.fetch!(params, :start_date),
      status: :running,
      inserted_at: now,
      updated_at: now
    })
  end

  @spec load(Path.t()) :: {:ok, t()} | {:error, :not_found | :invalid}
  def load(dest_dir) do
    with {:ok, content} <- read_manifest_file(dest_dir),
         {:ok, json} <- Jason.decode(content) do
      from_json(json)
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} -> {:error, :invalid}
    end
  end

  # Write to a tmp file then rename over the manifest path (same-filesystem
  # rename is atomic) so a reader never observes a torn/partial JSON file.
  @spec save!(t(), Path.t()) :: t()
  def save!(%__MODULE__{} = manifest, dest_dir) do
    manifest = %{manifest | updated_at: DateTime.utc_now()}

    tmp_path =
      Path.join(dest_dir, ".export_manifest.json.tmp-#{System.unique_integer([:positive])}")

    File.write!(tmp_path, Jason.encode!(manifest, pretty: true))
    File.rename!(tmp_path, manifest_path(dest_dir))
    manifest
  end

  defp read_manifest_file(dest_dir) do
    case File.read(manifest_path(dest_dir)) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :not_found}
      {:error, _reason} -> {:error, :invalid}
    end
  end

  defp from_json(json) do
    {:ok,
     %__MODULE__{
       version: Map.fetch!(json, "version"),
       device_id: Map.fetch!(json, "device_id"),
       stream: String.to_existing_atom(Map.fetch!(json, "stream")),
       start_date: parse_date!(Map.fetch!(json, "start_date")),
       end_date: parse_date!(Map.fetch!(json, "end_date")),
       max_duration: Map.get(json, "max_duration"),
       max_file_size: Map.get(json, "max_file_size"),
       cursor: parse_date!(Map.fetch!(json, "cursor")),
       status: String.to_existing_atom(Map.fetch!(json, "status")),
       error: Map.get(json, "error"),
       files: Enum.map(Map.get(json, "files", []), &file_entry_from_json/1),
       inserted_at: parse_date!(Map.fetch!(json, "inserted_at")),
       updated_at: parse_date!(Map.fetch!(json, "updated_at"))
     }}
  rescue
    _error -> {:error, :invalid}
  end

  defp file_entry_from_json(json) do
    %{
      filename: Map.fetch!(json, "filename"),
      start_date: parse_date!(Map.fetch!(json, "start_date")),
      end_date: parse_date!(Map.fetch!(json, "end_date")),
      size: Map.fetch!(json, "size")
    }
  end

  defp parse_date!(iso8601) do
    {:ok, date, _offset} = DateTime.from_iso8601(iso8601)
    date
  end
end
