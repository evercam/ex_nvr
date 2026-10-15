defmodule ExNVR.Export.S3 do
  @moduledoc """
  S3 destination for footage exports.

  Objects follow Evercam's footage layout, in the device's local time:

      <kit_id>/<camera_id>/YYYY/MM/DD/HH/MM_SS.mp4

  and a job manifest is written to `<kit_id>/<camera_id>/exports/<job_id>.json`
  once the job completes.
  """

  require Logger

  alias ExAws.S3
  alias ExNVR.Export.Manifest
  alias ExNVR.Model.Device
  alias ExNVR.RemoteStorage

  @upload_opts [content_type: "video/mp4", max_concurrency: 2, timeout: to_timeout(minute: 2)]

  @doc """
  This kit's id, the default root of the object keys. Set by the firmware as
  `config :ex_nvr, :kit_id`, either a value or a zero-arity function read
  each time (the kit may be configured after boot).
  """
  @spec kit_id() :: String.t() | nil
  def kit_id do
    case Application.get_env(:ex_nvr, :kit_id) do
      fun when is_function(fun, 0) -> fun.()
      kit_id -> kit_id
    end
  end

  @doc """
  Resolves the staging directory (the job's identity) and the destination to
  pass to `ExNVR.Export.start/6`. A blank `camera_id` falls back to the
  device id and a blank `:kit_id` option to `kit_id/0`.
  """
  @spec job(
          Device.t(),
          RemoteStorage.t(),
          atom(),
          String.t() | nil,
          DateTime.t(),
          DateTime.t(),
          kit_id: String.t() | nil
        ) ::
          {:ok, %{dest_dir: Path.t(), destination: Manifest.destination()}}
          | {:error, :missing_kit_id | :no_storage}
  def job(device, remote_storage, stream, camera_id, start_date, end_date, opts \\ []) do
    camera_id = if camera_id in [nil, ""], do: device.id, else: camera_id
    kit_id = if opts[:kit_id] in [nil, ""], do: kit_id(), else: opts[:kit_id]

    with {:kit_id, kit_id} when is_binary(kit_id) and kit_id != "" <- {:kit_id, kit_id},
         job_id = job_id(remote_storage, device, stream, kit_id, camera_id, start_date, end_date),
         {:dir, dest_dir} when is_binary(dest_dir) <- {:dir, staging_dir(device, job_id)} do
      destination = %{
        type: :s3,
        remote_storage_id: remote_storage.id,
        kit_id: kit_id,
        camera_id: camera_id,
        job_id: job_id
      }

      {:ok, %{dest_dir: dest_dir, destination: destination}}
    else
      {:kit_id, _kit_id} -> {:error, :missing_kit_id}
      {:dir, _dir} -> {:error, :no_storage}
    end
  end

  # Deterministic: the same inputs always resolve to the same job.
  defp job_id(remote_storage, device, stream, kit_id, camera_id, start_date, end_date) do
    hash =
      [
        to_string(remote_storage.id),
        device.id,
        to_string(stream),
        kit_id,
        camera_id,
        # unix time so precision/zone differences don't change the identity
        to_string(DateTime.to_unix(start_date, :microsecond)),
        to_string(DateTime.to_unix(end_date, :microsecond))
      ]
      |> Enum.join("|")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    Calendar.strftime(start_date, "%Y%m%dT%H%M%SZ") <> "_" <> hash
  end

  @doc "Local directory where files are staged before upload. Also the job's identity."
  @spec staging_dir(Device.t(), String.t()) :: Path.t() | nil
  def staging_dir(device, job_id) do
    if base_dir = Device.base_dir(device), do: Path.join([base_dir, "s3_exports", job_id])
  end

  @spec object_key(Manifest.destination(), DateTime.t(), String.t()) :: String.t()
  def object_key(destination, start_date, timezone) do
    local_start = DateTime.shift_zone!(start_date, timezone)

    Path.join([
      destination.kit_id,
      destination.camera_id,
      Calendar.strftime(local_start, "%Y/%m/%d/%H/%M_%S.mp4")
    ])
  end

  @spec manifest_key(Manifest.destination()) :: String.t()
  def manifest_key(destination) do
    Path.join([
      destination.kit_id,
      destination.camera_id,
      "exports",
      destination.job_id <> ".json"
    ])
  end

  @doc """
  Uploads a local file. Skipped when an object of the same size already
  exists at `key`; an object of a different size (e.g. a partial hour from an
  earlier, shorter export) is overwritten and its previous size returned.
  """
  @spec upload_file(Path.t(), String.t(), Keyword.t()) ::
          {:ok, :uploaded | :skipped | {:overwritten, non_neg_integer()}} | {:error, term()}
  def upload_file(path, key, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    size = File.stat!(path).size

    case remote_size(bucket, key, opts) do
      {:ok, ^size} ->
        {:ok, :skipped}

      {:ok, previous_size} ->
        Logger.warning("[S3 export] overwriting #{key} (#{previous_size} -> #{size} bytes)")

        with {:ok, :uploaded} <- do_upload(path, bucket, key, opts),
             do: {:ok, {:overwritten, previous_size}}

      :not_found ->
        do_upload(path, bucket, key, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec put_json(String.t(), map(), Keyword.t()) :: :ok | {:error, term()}
  def put_json(key, data, opts) do
    opts
    |> Keyword.fetch!(:bucket)
    |> S3.put_object(key, Jason.encode!(data, pretty: true), content_type: "application/json")
    |> ExAws.request(opts)
    |> case do
      {:ok, _resp} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Retrying these won't help: the request itself or the configuration is wrong.
  @permanent_statuses [301, 400, 401, 403, 404, 405]

  @doc "Whether an upload error needs a configuration change rather than a retry."
  @spec permanent_error?(term()) :: boolean()
  def permanent_error?({:http_error, status, _resp}), do: status in @permanent_statuses
  def permanent_error?(_reason), do: false

  @doc "A short, human readable description of an upload error."
  @spec describe_error(term()) :: String.t()
  def describe_error({:http_error, status, resp}) do
    body = if is_map(resp), do: Map.get(resp, :body, ""), else: ""

    detail =
      case {xml_tag(body, "Code"), xml_tag(body, "Message")} do
        {nil, _message} -> status_hint(status)
        {code, nil} -> code
        {code, message} -> "#{code}: #{message}"
      end

    "HTTP #{status} #{detail}"
  end

  def describe_error(:staged_file_missing), do: "the staged file to upload is missing"
  def describe_error({:upload_crashed, reason}), do: "upload crashed: #{short_inspect(reason)}"
  def describe_error(reason), do: short_inspect(reason)

  defp status_hint(301), do: "the bucket is in a different region than configured"
  defp status_hint(400), do: "bad request, check the bucket name and region"
  defp status_hint(status) when status in [401, 403], do: "access denied, check the credentials"
  defp status_hint(404), do: "not found, check the bucket name"
  defp status_hint(status) when status >= 500, do: "S3 server error"
  defp status_hint(_status), do: "request failed"

  defp xml_tag(body, tag) when is_binary(body) do
    case Regex.run(~r{<#{tag}>(.*?)</#{tag}>}s, body) do
      [_, value] -> value
      nil -> nil
    end
  end

  defp xml_tag(_body, _tag), do: nil

  defp short_inspect(term), do: term |> inspect() |> String.slice(0, 200)

  defp do_upload(path, bucket, key, opts) do
    path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket, key, @upload_opts)
    |> ExAws.request(opts)
    |> case do
      {:ok, _resp} -> {:ok, :uploaded}
      {:error, reason} -> {:error, reason}
    end
  end

  # Write-only credentials commonly can't HEAD (403); treat that as unknown
  # and upload rather than failing the job.
  defp remote_size(bucket, key, opts) do
    case bucket |> S3.head_object(key) |> ExAws.request(opts) do
      {:ok, %{headers: headers}} ->
        {:ok, content_length(headers)}

      {:error, {:http_error, status, _resp}} when status in [403, 404] ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp content_length(headers) do
    Enum.find_value(headers, fn {name, value} ->
      if String.downcase(name) == "content-length" do
        value |> List.wrap() |> List.first() |> String.to_integer()
      end
    end)
  end
end
