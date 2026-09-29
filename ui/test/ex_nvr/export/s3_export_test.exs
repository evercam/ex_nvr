defmodule ExNVR.Export.S3ExportTest do
  use ExNVR.DataCase

  import ExNVR.RemoteStoragesFixtures

  alias ExNVR.Export
  alias ExNVR.Export.{Manifest, S3}

  @moduletag :tmp_dir

  @kit_id "kit-42"
  @bucket "footage"

  setup %{tmp_dir: tmp_dir} do
    bypass = Bypass.open()
    {:ok, store} = Agent.start_link(fn -> %{objects: %{}, parts: %{}, requests: []} end)
    Bypass.stub(bypass, :any, :any, &fake_s3(&1, store))

    remote_storage =
      remote_storage_fixture(%{
        url: "http://localhost:#{bypass.port}",
        s3_config: %{
          bucket: @bucket,
          region: "us-east-1",
          access_key_id: "access-key",
          secret_access_key: "secret",
          kit_id: @kit_id
        }
      })

    device = camera_device_fixture(tmp_dir, %{timezone: "Europe/Paris"})

    Application.put_env(:ex_nvr, :export_upload_retry_base_ms, 1)
    on_exit(fn -> Application.delete_env(:ex_nvr, :export_upload_retry_base_ms) end)

    %{bypass: bypass, store: store, remote_storage: remote_storage, device: device}
  end

  defp recordings(device, starts) do
    for start_date <- starts do
      recording_fixture(device, start_date: start_date, end_date: DateTime.add(start_date, 5))
    end
  end

  defp start_s3(device, remote_storage, start_date, end_date, opts \\ []) do
    {:ok, job} =
      S3.job(device, remote_storage, :high, opts[:camera_id], start_date, end_date)

    {:ok, _pid} =
      Export.start(device, :high, start_date, end_date, job.dest_dir,
        split: :hourly,
        destination: job.destination,
        force: Keyword.get(opts, :force, false)
      )

    job
  end

  defp wait_finished(dest_dir, attempts \\ 300)
  defp wait_finished(_dest_dir, 0), do: flunk("export did not finish in time")

  defp wait_finished(dest_dir, attempts) do
    case Export.progress(dest_dir) do
      {:ok, %{status: status} = progress} when status in [:completed, :failed] ->
        # the worker may still be tearing down
        Process.sleep(20)
        {:ok, progress}

      _other ->
        Process.sleep(10)
        wait_finished(dest_dir, attempts - 1)
    end
  end

  defp object_keys(store), do: store |> Agent.get(& &1.objects) |> Map.keys() |> Enum.sort()

  test "splits on local clock hours and uploads with the Evercam layout", %{
    device: device,
    remote_storage: remote_storage,
    store: store
  } do
    # 11:59:50 -> 12:00:05 Europe/Paris
    recordings(device, [
      ~U(2024-12-15T10:59:50.000000Z),
      ~U(2024-12-15T10:59:55.000000Z),
      ~U(2024-12-15T11:00:00.000000Z)
    ])

    job = start_s3(device, remote_storage, ~U(2024-12-15T10:59:50Z), ~U(2024-12-15T11:00:05Z))

    assert {:ok, %{status: :completed, files: files, files_uploaded: 2}} =
             wait_finished(job.dest_dir)

    prefix = "#{@kit_id}/#{device.id}"

    assert Enum.map(files, & &1.key) == [
             "#{prefix}/2024/12/15/11/59_50.mp4",
             "#{prefix}/2024/12/15/12/00_00.mp4"
           ]

    assert Enum.all?(files, &(&1.upload_status == :uploaded))

    manifest_key = "#{prefix}/exports/#{job.destination.job_id}.json"
    assert object_keys(store) == Enum.sort([manifest_key | Enum.map(files, & &1.key)])

    # staged files are removed once uploaded, only the local manifest remains
    assert File.ls!(job.dest_dir) == [".export_manifest.json"]

    remote_manifest = Agent.get(store, & &1.objects[manifest_key]) |> Jason.decode!()
    assert remote_manifest["camera_id"] == device.id
    assert length(remote_manifest["files"]) == 2

    [first | _] = files
    {:ok, reader} = ExMP4.Reader.new(write_tmp(store, first.key))
    assert ExMP4.Reader.duration(reader, :millisecond) == 10_000
  end

  test "uses the camera id override", %{device: device, remote_storage: remote_storage} do
    recordings(device, [~U(2024-12-15T11:00:00.000000Z)])

    job =
      start_s3(device, remote_storage, ~U(2024-12-15T11:00:00Z), ~U(2024-12-15T11:00:05Z),
        camera_id: "evercam-cam"
      )

    assert {:ok, %{status: :completed, files: [file]}} = wait_finished(job.dest_dir)
    assert file.key == "#{@kit_id}/evercam-cam/2024/12/15/12/00_00.mp4"
  end

  test "starts a new file after a gap longer than 5 minutes only", %{
    device: device,
    remote_storage: remote_storage
  } do
    recordings(device, [
      ~U(2024-12-15T11:00:00.000000Z),
      # 2 minute gap: joined
      ~U(2024-12-15T11:02:05.000000Z),
      # 6 minute gap: new file
      ~U(2024-12-15T11:08:10.000000Z)
    ])

    job = start_s3(device, remote_storage, ~U(2024-12-15T11:00:00Z), ~U(2024-12-15T11:30:00Z))

    assert {:ok, %{status: :completed, files: files}} = wait_finished(job.dest_dir)

    assert Enum.map(files, &Path.basename(&1.key)) == ["00_00.mp4", "08_10.mp4"]
  end

  test "skips objects that already exist with the same size", %{
    device: device,
    remote_storage: remote_storage,
    store: store
  } do
    recordings(device, [~U(2024-12-15T11:00:00.000000Z)])
    start_date = ~U(2024-12-15T11:00:00Z)
    end_date = ~U(2024-12-15T11:00:05Z)

    job = start_s3(device, remote_storage, start_date, end_date)
    assert {:ok, %{status: :completed}} = wait_finished(job.dest_dir)

    # Same footage, different job (other end date) -> same key and size
    Agent.update(store, &%{&1 | requests: []})
    job = start_s3(device, remote_storage, start_date, DateTime.add(end_date, 60))

    assert {:ok, %{status: :completed, files: [file]}} = wait_finished(job.dest_dir)
    assert file.upload_status == :skipped

    methods = store |> Agent.get(& &1.requests) |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    # only HEAD for the video + PUT for the job manifest; no multipart upload
    refute "POST" in methods

    remote_manifest = remote_manifest(store, job)
    assert remote_manifest["skipped"] == [file.key]
    assert remote_manifest["overwritten"] == []
  end

  test "overwrites objects of a different size and flags them", %{
    device: device,
    remote_storage: remote_storage,
    store: store
  } do
    recordings(device, [~U(2024-12-15T11:00:00.000000Z)])
    key = "#{@kit_id}/#{device.id}/2024/12/15/12/00_00.mp4"
    Agent.update(store, &put_in(&1, [:objects, key], "partial"))

    job = start_s3(device, remote_storage, ~U(2024-12-15T11:00:00Z), ~U(2024-12-15T11:00:05Z))

    assert {:ok, %{status: :completed, files: [file], files_uploaded: 1}} =
             wait_finished(job.dest_dir)

    assert %{key: ^key, upload_status: :overwritten, previous_size: 7} = file
    assert byte_size(Agent.get(store, & &1.objects[key])) == file.size

    # survives a reload from disk
    assert {:ok, %{files: [%{upload_status: :overwritten, previous_size: 7}]}} =
             Manifest.load(job.dest_dir)

    remote_manifest = remote_manifest(store, job)
    assert remote_manifest["skipped"] == []

    assert remote_manifest["overwritten"] == [
             %{"key" => key, "size" => file.size, "previous_size" => 7}
           ]
  end

  defp remote_manifest(store, job) do
    key = S3.manifest_key(job.destination)
    store |> Agent.get(& &1.objects[key]) |> Jason.decode!()
  end

  test "retries transient errors, then fails the job, and resumes pending uploads on retry", %{
    device: device,
    remote_storage: remote_storage,
    store: store
  } do
    recordings(device, [~U(2024-12-15T11:00:00.000000Z)])
    start_date = ~U(2024-12-15T11:00:00Z)
    end_date = ~U(2024-12-15T11:00:05Z)

    Agent.update(store, &Map.put(&1, :fail?, 429))
    job = start_s3(device, remote_storage, start_date, end_date)

    assert {:ok, %{status: :failed, error: error, files: [file]}} = wait_finished(job.dest_dir)
    assert error == "upload failed: HTTP 429 SlowDown: Please reduce your request rate."
    # 6 attempts, each starting with a HEAD
    assert store |> Agent.get(& &1.requests) |> Enum.count(&(elem(&1, 0) == "HEAD")) == 6

    assert file.upload_status == :pending
    assert File.exists?(Path.join(job.dest_dir, file.filename))

    Agent.update(store, &Map.put(&1, :fail?, false))
    start_s3(device, remote_storage, start_date, end_date, force: true)

    assert {:ok, %{status: :completed, files: [file]}} = wait_finished(job.dest_dir)
    assert file.upload_status == :uploaded
    assert file.key in object_keys(store)
  end

  test "fails straight away on permanent errors with a readable message", %{
    device: device,
    remote_storage: remote_storage,
    store: store
  } do
    recordings(device, [~U(2024-12-15T11:00:00.000000Z)])
    Agent.update(store, &Map.put(&1, :fail?, 403))
    job = start_s3(device, remote_storage, ~U(2024-12-15T11:00:00Z), ~U(2024-12-15T11:00:05Z))

    assert {:ok, %{status: :failed, error: error}} = wait_finished(job.dest_dir)
    assert error == "upload failed: HTTP 403 AccessDenied: Access Denied"
    # a single attempt: HEAD (403 means unknown), then the refused upload
    assert store |> Agent.get(& &1.requests) |> Enum.map(&elem(&1, 0)) == ["POST", "HEAD"]
  end

  test "marks the job failed when a recording disappears mid-export", %{
    device: device,
    remote_storage: remote_storage
  } do
    [recording | _] = recordings(device, [~U(2024-12-15T11:00:00.000000Z)])
    File.rm!(ExNVR.Recordings.recording_path(device, :high, recording))

    job = start_s3(device, remote_storage, ~U(2024-12-15T11:00:00Z), ~U(2024-12-15T11:00:05Z))

    assert {:ok,
            %{status: :failed, error: "a recording was deleted while it was being exported" <> _}} =
             wait_finished(job.dest_dir)
  end

  test "a job left running without a worker is reported as interrupted", %{
    device: device,
    remote_storage: remote_storage,
    store: store
  } do
    recordings(device, [~U(2024-12-15T11:00:00.000000Z)])
    start_date = ~U(2024-12-15T11:00:00Z)
    end_date = ~U(2024-12-15T11:00:05Z)
    {:ok, job} = S3.job(device, remote_storage, :high, nil, start_date, end_date)
    File.mkdir_p!(job.dest_dir)

    %{device_id: device.id, stream: :high, start_date: start_date, end_date: end_date}
    |> Map.merge(%{split: :hourly, timezone: device.timezone, destination: job.destination})
    |> Manifest.new()
    |> Manifest.save!(job.dest_dir)

    assert {:ok, %{status: :paused, error: "interrupted" <> _}} = Export.progress(job.dest_dir)

    # and it resumes like a paused job
    start_s3(device, remote_storage, start_date, end_date)
    assert {:ok, %{status: :completed, files: [_file]}} = wait_finished(job.dest_dir)
    assert length(object_keys(store)) == 2
  end

  test "list_recent/1 lists jobs newest first, even when their folder is gone", %{
    device: device,
    remote_storage: remote_storage
  } do
    recordings(device, [~U(2024-12-15T11:00:00.000000Z)])

    first = start_s3(device, remote_storage, ~U(2024-12-15T11:00:00Z), ~U(2024-12-15T11:00:05Z))
    wait_finished(first.dest_dir)
    second = start_s3(device, remote_storage, ~U(2024-12-15T11:00:00Z), ~U(2024-12-15T11:00:04Z))
    wait_finished(second.dest_dir)

    assert [
             %{
               dest_dir: dest_2,
               kind: :s3,
               progress: %{status: :completed},
               manifest: %Manifest{}
             },
             %{dest_dir: dest_1}
           ] = Export.list_recent()

    assert {dest_1, dest_2} == {first.dest_dir, second.dest_dir}

    File.rm_rf!(first.dest_dir)
    assert [_, %{dest_dir: ^dest_1, manifest: nil, progress: nil}] = Export.list_recent()
  end

  test "describe_error/1 extracts the S3 error or explains the status" do
    body =
      "<Error><Code>InvalidBucketName</Code><Message>The specified bucket is not valid.</Message></Error>"

    assert S3.describe_error({:http_error, 400, %{body: body}}) ==
             "HTTP 400 InvalidBucketName: The specified bucket is not valid."

    # HEAD responses carry no body
    assert S3.describe_error({:http_error, 400, %{body: ""}}) ==
             "HTTP 400 bad request, check the bucket name and region"

    assert S3.permanent_error?({:http_error, 400, %{}})
    refute S3.permanent_error?({:http_error, 503, %{}})
    refute S3.permanent_error?(:timeout)
  end

  test "holds generation back while uploads are pending, then finishes", %{
    device: device,
    remote_storage: remote_storage,
    store: store
  } do
    starts = for h <- 0..4, do: DateTime.add(~U(2024-12-15T11:00:00.000000Z), h * 3600)
    recordings(device, starts)

    Agent.update(store, &Map.put(&1, :delay, 50))
    job = start_s3(device, remote_storage, hd(starts), DateTime.add(List.last(starts), 5))

    Process.sleep(60)
    staged = job.dest_dir |> File.ls!() |> Enum.count(&String.ends_with?(&1, ".mp4"))
    # 2 finalized files waiting for upload + at most 1 being written
    assert staged <= 3

    assert {:ok, %{status: :completed, files: files, files_uploaded: 5}} =
             wait_finished(job.dest_dir)

    assert length(files) == 5
  end

  test "stop/1 pauses while uploads are pending and resume completes them", %{
    device: device,
    remote_storage: remote_storage,
    store: store
  } do
    recordings(device, [~U(2024-12-15T11:00:00.000000Z)])
    start_date = ~U(2024-12-15T11:00:00Z)
    end_date = ~U(2024-12-15T11:00:05Z)

    Application.put_env(:ex_nvr, :export_upload_retry_base_ms, 60_000)
    Agent.update(store, &Map.put(&1, :fail?, 429))
    job = start_s3(device, remote_storage, start_date, end_date)

    # wait for the first failed attempt; the job then sits in its retry delay
    wait_until(fn -> Agent.get(store, &(&1.requests != [])) end)
    Process.sleep(50)

    assert :ok = Export.stop(job.dest_dir)

    assert {:ok, %{status: :paused, files: [%{upload_status: :pending}]}} =
             Export.progress(job.dest_dir)

    Agent.update(store, &Map.put(&1, :fail?, false))
    start_s3(device, remote_storage, start_date, end_date)

    assert {:ok, %{status: :completed, files: [%{upload_status: :uploaded}]}} =
             wait_finished(job.dest_dir)
  end

  defp wait_until(fun, attempts \\ 200)
  defp wait_until(_fun, 0), do: flunk("condition not met in time")

  defp wait_until(fun, attempts) do
    if fun.(), do: :ok, else: Process.sleep(10) && wait_until(fun, attempts - 1)
  end

  test "job/6 requires a kit id", %{device: device, remote_storage: remote_storage} do
    remote_storage = %{remote_storage | s3_config: %{remote_storage.s3_config | kit_id: nil}}

    assert {:error, :missing_kit_id} =
             S3.job(device, remote_storage, :high, nil, DateTime.utc_now(), DateTime.utc_now())

    Application.put_env(:ex_nvr, :kit_id, "fw-kit")
    on_exit(fn -> Application.delete_env(:ex_nvr, :kit_id) end)

    assert {:ok, %{destination: %{kit_id: "fw-kit"}}} =
             S3.job(device, remote_storage, :high, nil, DateTime.utc_now(), DateTime.utc_now())
  end

  test "next_hour_boundary/2 follows the local clock, including DST" do
    # Europe/Paris falls back at 03:00 CEST (01:00 UTC) on 2024-10-27
    assert Export.Worker.next_hour_boundary(~U(2024-10-27T00:30:00Z), "Europe/Paris") ==
             ~U(2024-10-27T01:00:00.000000Z)

    assert Export.Worker.next_hour_boundary(~U(2024-10-27T01:30:00Z), "Europe/Paris") ==
             ~U(2024-10-27T02:00:00.000000Z)

    assert Export.Worker.next_hour_boundary(~U(2024-12-15T10:15:00Z), "Asia/Kolkata") ==
             ~U(2024-12-15T10:30:00.000000Z)
  end

  test "manifest round-trips remote fields", %{tmp_dir: tmp_dir} do
    destination = %{
      type: :s3,
      remote_storage_id: 1,
      kit_id: "k",
      camera_id: "c",
      job_id: "j"
    }

    %{
      device_id: "d",
      stream: :high,
      start_date: ~U(2024-12-15T11:00:00Z),
      end_date: ~U(2024-12-15T12:00:00Z),
      split: :hourly,
      timezone: "Europe/Paris",
      destination: destination
    }
    |> Manifest.new()
    |> Map.put(:files, [
      %{
        filename: "export_00000.mp4",
        start_date: ~U(2024-12-15T11:00:00Z),
        end_date: ~U(2024-12-15T12:00:00Z),
        size: 1,
        key: "k/c/2024/12/15/12/00_00.mp4",
        upload_status: :pending
      }
    ])
    |> Manifest.save!(tmp_dir)

    assert {:ok, manifest} = Manifest.load(tmp_dir)
    assert manifest.split == :hourly
    assert manifest.timezone == "Europe/Paris"
    assert manifest.destination == destination
    assert [%{upload_status: :pending, key: "k/c/2024/12/15/12/00_00.mp4"}] = manifest.files
  end

  defp write_tmp(store, key) do
    path = Path.join(System.tmp_dir!(), "s3_export_#{System.unique_integer([:positive])}.mp4")
    File.write!(path, Agent.get(store, & &1.objects[key]))
    on_exit(fn -> File.rm(path) end)
    path
  end

  ## Minimal in-memory S3 (path-style)

  defp fake_s3(conn, store) do
    conn = Plug.Conn.fetch_query_params(conn)
    {:ok, body, conn} = read_full_body(conn)
    "/" <> path = conn.request_path
    [@bucket, key] = String.split(path, "/", parts: 2)
    key = URI.decode(key)

    Agent.update(store, &%{&1 | requests: [{conn.method, key} | &1.requests]})
    fail? = Agent.get(store, &Map.get(&1, :fail?, false))
    if delay = Agent.get(store, &Map.get(&1, :delay)), do: Process.sleep(delay)

    handle_s3(conn, store, conn.method, key, conn.query_params, body, fail?)
  end

  defp handle_s3(conn, store, "HEAD", key, _params, _body, _fail?) do
    case Agent.get(store, & &1.objects[key]) do
      nil -> Plug.Conn.send_resp(conn, 404, "")
      object -> Plug.Conn.send_resp(conn, 200, object)
    end
  end

  defp handle_s3(conn, _store, _method, _key, _params, _body, 403) do
    Plug.Conn.send_resp(
      conn,
      403,
      "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>"
    )
  end

  defp handle_s3(conn, _store, _method, _key, _params, _body, 429) do
    Plug.Conn.send_resp(
      conn,
      429,
      "<Error><Code>SlowDown</Code><Message>Please reduce your request rate.</Message></Error>"
    )
  end

  defp handle_s3(conn, _store, "POST", key, %{"uploads" => _}, _body, _fail?) do
    Plug.Conn.send_resp(conn, 200, """
    <InitiateMultipartUploadResult>
      <Bucket>#{@bucket}</Bucket><Key>#{key}</Key><UploadId>upload-1</UploadId>
    </InitiateMultipartUploadResult>
    """)
  end

  defp handle_s3(conn, store, "PUT", key, %{"partNumber" => part}, body, _fail?) do
    Agent.update(store, &put_in(&1, [:parts, {key, String.to_integer(part)}], body))

    conn
    |> Plug.Conn.put_resp_header("etag", "\"etag-#{part}\"")
    |> Plug.Conn.send_resp(200, "")
  end

  defp handle_s3(conn, store, "POST", key, %{"uploadId" => _}, _body, _fail?) do
    Agent.update(store, fn state ->
      {parts, rest} = Enum.split_with(state.parts, fn {{k, _}, _} -> k == key end)
      object = parts |> Enum.sort_by(fn {{_, n}, _} -> n end) |> Enum.map_join(&elem(&1, 1))
      %{state | parts: Map.new(rest), objects: Map.put(state.objects, key, object)}
    end)

    Plug.Conn.send_resp(conn, 200, """
    <CompleteMultipartUploadResult>
      <Bucket>#{@bucket}</Bucket><Key>#{key}</Key><ETag>"final"</ETag>
    </CompleteMultipartUploadResult>
    """)
  end

  defp handle_s3(conn, store, "PUT", key, _params, body, _fail?) do
    Agent.update(store, &put_in(&1, [:objects, key], body))
    Plug.Conn.send_resp(conn, 200, "")
  end

  defp read_full_body(conn, acc \\ []) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, conn} -> {:ok, IO.iodata_to_binary([acc, body]), conn}
      {:more, body, conn} -> read_full_body(conn, [acc, body])
    end
  end
end
