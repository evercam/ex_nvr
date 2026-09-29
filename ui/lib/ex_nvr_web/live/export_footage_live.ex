defmodule ExNVRWeb.ExportFootageLive do
  use ExNVRWeb, :live_view

  alias Ecto.Changeset
  alias ExNVR.{Devices, Disk, Export, RemoteStorages}
  alias ExNVR.Export.S3
  alias ExNVR.Model.Device

  @poll_interval to_timeout(second: 2)
  @folder_name_regex ~r/^[a-zA-Z0-9_.-]+$/

  @kib 1024
  @mib 1024 * 1024
  @gib 1024 * 1024 * 1024
  @tib 1024 * 1024 * 1024 * 1024

  @default_lookback_minutes 15

  @default_max_duration 3_600
  @default_max_file_size_mb 4_096

  @types %{
    device_id: :string,
    start_date: :naive_datetime,
    end_date: :naive_datetime,
    max_duration: :integer,
    max_file_size_mb: :integer,
    storage_mountpoint: :string,
    folder_name: :string,
    destination: :string,
    remote_storage_id: :integer,
    stream: :string,
    camera_id: :string
  }

  def mount(raw_params, _session, socket) do
    devices = Devices.list()
    params = initial_params(raw_params)
    default_dates = default_dates(devices, params["device_id"])

    socket
    |> assign(
      devices: devices,
      default_dates: {params["device_id"], default_dates},
      recent_exports: Export.list_recent(),
      active_tab: if(params_tab(raw_params) == "recent", do: "recent", else: "export"),
      disks: Disk.list_drives!(),
      remote_storages: Enum.filter(RemoteStorages.list(), &(&1.type == :s3)),
      dest_dir: nil,
      job_status: :new,
      job_progress: nil,
      poll_timer: nil
    )
    |> then(
      &assign(&1,
        export_form: to_form(export_changeset(Map.merge(params, default_dates), &1), as: "export")
      )
    )
    |> then(&{:ok, &1})
  end

  defp initial_params(%{"device_id" => device_id}), do: %{"device_id" => device_id}
  defp initial_params(_params), do: %{}

  defp params_tab(%{"tab" => tab}), do: tab
  defp params_tab(_params), do: nil

  # "now" and 15 minutes ago, in the device's timezone since that's how the
  # form's dates are interpreted. Without a device, use the first one's.
  defp default_dates(devices, device_id) do
    timezone =
      case Enum.find(devices, &(&1.id == device_id)) || List.first(devices) do
        nil -> "Etc/UTC"
        device -> device.timezone
      end

    now = timezone |> DateTime.now!() |> DateTime.to_naive()

    %{
      "start_date" =>
        format_datetime_local(NaiveDateTime.add(now, -@default_lookback_minutes, :minute)),
      "end_date" => format_datetime_local(now)
    }
  end

  @doc false
  # Only the streams the device actually records can be exported.
  def stream_options(devices, device_id) do
    device = Enum.find(devices, &(&1.id == device_id))

    if device && Device.has_sub_stream(device) &&
         device.storage_config.record_sub_stream == :always,
       do: [{"Main stream", "high"}, {"Sub stream", "low"}],
       else: [{"Main stream", "high"}]
  end

  defp allowed_streams(socket, device_id),
    do: socket.assigns.devices |> stream_options(device_id) |> Enum.map(&elem(&1, 1))

  defp reset_unrecorded_stream(socket, %{"stream" => stream} = params) do
    if stream in allowed_streams(socket, params["device_id"]),
      do: params,
      else: Map.put(params, "stream", "high")
  end

  defp reset_unrecorded_stream(_socket, params), do: params

  defp load_recent(socket), do: assign(socket, recent_exports: Export.list_recent())

  # Rebuilds the form inputs that resolve to this job's destination, so
  # resume/retry from the opened form targets the same job.
  defp params_from_job(job, manifest, device) do
    local = &(&1 |> DateTime.shift_zone!(device.timezone) |> DateTime.to_naive())

    base = %{
      "device_id" => device.id,
      "start_date" => format_datetime_local(local.(manifest.start_date)),
      "end_date" => format_datetime_local(local.(manifest.end_date)),
      "stream" => to_string(manifest.stream)
    }

    case manifest.destination do
      %{type: :s3} = destination ->
        Map.merge(base, %{
          "destination" => "s3",
          "remote_storage_id" => destination.remote_storage_id,
          "camera_id" =>
            if(destination.camera_id == device.id, do: "", else: destination.camera_id)
        })

      nil ->
        Map.merge(base, %{
          "destination" => "usb",
          "storage_mountpoint" => Path.dirname(job.dest_dir),
          "folder_name" => Path.basename(job.dest_dir),
          "max_duration" => manifest.max_duration,
          "max_file_size_mb" => manifest.max_file_size && div(manifest.max_file_size, @mib)
        })
    end
  end

  @doc false
  def job_destination_label(%{manifest: %{destination: %{type: :s3} = dest}}, remote_storages) do
    storage = Enum.find(remote_storages, &(&1.id == dest.remote_storage_id))
    name = if storage, do: storage.name, else: "deleted storage"
    "S3 · #{name} · #{dest.kit_id}/#{dest.camera_id}/"
  end

  def job_destination_label(%{dest_dir: dest_dir}, _remote_storages), do: "USB · #{dest_dir}"

  @doc false
  def job_range_label(%{manifest: nil}, _devices), do: "—"

  def job_range_label(%{manifest: manifest}, devices) do
    timezone =
      case Enum.find(devices, &(&1.id == manifest.device_id)) do
        nil -> "Etc/UTC"
        device -> device.timezone
      end

    fmt = &(&1 |> DateTime.shift_zone!(timezone) |> Calendar.strftime("%Y-%m-%d %H:%M"))
    "#{fmt.(manifest.start_date)} → #{fmt.(manifest.end_date)}"
  end

  @doc false
  def job_device_name(%{device_id: device_id}, devices) do
    case Enum.find(devices, &(&1.id == device_id)) do
      nil -> "deleted device"
      device -> device.name
    end
  end

  @doc false
  def job_status(%{progress: nil}), do: :unavailable
  def job_status(%{progress: progress}), do: progress.status

  @doc false
  def job_files_label(%{progress: nil}), do: "—"

  def job_files_label(%{progress: %{remote?: true} = progress}),
    do: "#{progress.files_uploaded} / #{progress.files_completed} uploaded"

  def job_files_label(%{progress: progress}), do: "#{progress.files_completed} files"

  @doc false
  def job_flags_label(%{progress: %{remote?: true, files: files}}) do
    case upload_flags(files) do
      %{skipped: [], overwritten: []} -> nil
      %{skipped: s, overwritten: o} -> "#{length(s)} skipped, #{length(o)} overwritten"
    end
  end

  def job_flags_label(_job), do: nil

  @doc false
  def status_badge_class(:completed),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300"

  def status_badge_class(:running),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300"

  def status_badge_class(:paused),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300"

  def status_badge_class(:failed), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300"

  def status_badge_class(_status),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"

  defp format_datetime_local(naive), do: Calendar.strftime(naive, "%Y-%m-%dT%H:%M")

  # Untouched default dates follow the selected device's timezone.
  defp refresh_default_dates(%{assigns: %{default_dates: {device_id, dates}}} = socket, params) do
    if params["device_id"] != device_id and Map.take(params, ["start_date", "end_date"]) == dates do
      dates = default_dates(socket.assigns.devices, params["device_id"])
      {assign(socket, default_dates: {params["device_id"], dates}), Map.merge(params, dates)}
    else
      {socket, params}
    end
  end

  def handle_event("validate", %{"export" => params}, socket) do
    {socket, params} = refresh_default_dates(socket, params)
    params = reset_unrecorded_stream(socket, params)
    changeset = params |> export_changeset(socket) |> Map.put(:action, :validate)

    socket
    |> assign(export_form: to_form(changeset, as: "export"))
    |> refresh_dest_status(recompute_dest_dir(socket, params, changeset))
    |> then(&{:noreply, &1})
  end

  def handle_event("submit_export", %{"export" => params}, socket) do
    changeset = params |> export_changeset(socket) |> Map.put(:action, :insert)

    case Changeset.apply_action(changeset, :insert) do
      {:ok, data} ->
        do_start(socket, data, force: socket.assigns.job_status == :failed)

      {:error, changeset} ->
        {:noreply, assign(socket, export_form: to_form(changeset, as: "export"))}
    end
  end

  def handle_event("stop_export", _params, socket) do
    Export.stop(socket.assigns.dest_dir)

    socket
    |> refresh_dest_status(socket.assigns.dest_dir)
    |> load_recent()
    |> put_flash(:info, "Export stopped")
    |> then(&{:noreply, &1})
  end

  def handle_event("mount_disk", %{"part" => part_name}, socket) do
    case Enum.find(mountable_candidates(socket.assigns.disks), &(&1.name == part_name)) do
      nil -> {:noreply, socket}
      candidate -> mount_candidate(socket, candidate)
    end
  end

  def handle_event("open_export", %{"dest-dir" => dest_dir}, socket) do
    with %{manifest: %Export.Manifest{} = manifest} = job <-
           Enum.find(socket.assigns.recent_exports, &(&1.dest_dir == dest_dir)),
         %{} = device <- Enum.find(socket.assigns.devices, &(&1.id == manifest.device_id)) do
      params = params_from_job(job, manifest, device)

      socket
      |> assign(
        active_tab: "export",
        default_dates: {device.id, Map.take(params, ["start_date", "end_date"])},
        export_form: to_form(export_changeset(params, socket), as: "export")
      )
      |> refresh_dest_status(dest_dir)
      |> then(&{:noreply, &1})
    else
      _other -> {:noreply, put_flash(socket, :error, "This export can no longer be opened")}
    end
  end

  def handle_info({:tab_changed, %{tab: tab}}, socket),
    do: {:noreply, socket |> assign(active_tab: tab) |> load_recent()}

  def handle_info(:poll_progress, socket) do
    socket
    |> assign(poll_timer: nil)
    |> refresh_dest_status(socket.assigns.dest_dir)
    |> load_recent()
    |> then(&{:noreply, &1})
  end

  def terminate(_reason, %{assigns: %{poll_timer: ref}}) when ref != nil,
    do: Process.cancel_timer(ref)

  def terminate(_reason, _socket), do: :ok

  defp mount_root, do: Application.get_env(:ex_nvr, :export_mount_root, "/mnt/ex_nvr")

  defp mount_candidate(socket, candidate) do
    mountpoint = Path.join(mount_root(), candidate.name)

    with :ok <- File.mkdir_p(mountpoint),
         :ok <- do_mount(candidate, mountpoint) do
      socket
      |> assign(disks: Disk.list_drives!())
      |> put_flash(:info, "Mounted #{candidate.name} at #{mountpoint}")
      |> then(&{:noreply, &1})
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not mount #{candidate.name}: #{reason}")}
    end
  end

  # Ephemeral mount (not written to fstab) — gone on reboot/unplug, which is
  # the right default for a one-off export destination.
  defp do_mount(candidate, mountpoint) do
    case System.cmd("mount", ["-t", candidate.fs.type, candidate.path, mountpoint],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  defp do_start(socket, %{destination: "s3"} = data, opts) do
    device = Enum.find(socket.assigns.devices, &(&1.id == data.device_id))
    {:ok, job} = s3_job(socket, data)
    start_date = DateTime.from_naive!(data.start_date, device.timezone)
    end_date = DateTime.from_naive!(data.end_date, device.timezone)
    export_opts = [split: :hourly, destination: job.destination] |> Keyword.merge(opts)

    device
    |> Export.start(
      String.to_existing_atom(data.stream),
      start_date,
      end_date,
      job.dest_dir,
      export_opts
    )
    |> handle_start_result(socket, job.dest_dir)
  end

  defp do_start(socket, data, opts) do
    device = Enum.find(socket.assigns.devices, &(&1.id == data.device_id))
    dest_dir = Path.join(data.storage_mountpoint, data.folder_name)
    start_date = DateTime.from_naive!(data.start_date, device.timezone)
    end_date = DateTime.from_naive!(data.end_date, device.timezone)
    max_duration = Map.get(data, :max_duration)
    max_file_size_mb = Map.get(data, :max_file_size_mb)
    max_file_size = max_file_size_mb && max_file_size_mb * 1024 * 1024

    export_opts =
      [max_duration: max_duration, max_file_size: max_file_size] |> Keyword.merge(opts)

    device
    |> Export.start(:high, start_date, end_date, dest_dir, export_opts)
    |> handle_start_result(socket, dest_dir)
  end

  defp handle_start_result({:ok, _pid}, socket, dest_dir) do
    socket
    |> refresh_dest_status(dest_dir)
    |> load_recent()
    |> put_flash(:info, "Export started")
    |> then(&{:noreply, &1})
  end

  defp handle_start_result({:error, :device_mismatch}, socket, _dest_dir) do
    msg = "This folder already holds an export for a different device or stream"
    {:noreply, put_flash(socket, :error, msg)}
  end

  defp handle_start_result({:error, {:already_completed, _manifest}}, socket, dest_dir) do
    socket
    |> refresh_dest_status(dest_dir)
    |> put_flash(:info, "This export is already complete")
    |> then(&{:noreply, &1})
  end

  defp handle_start_result({:error, {:job_failed, _manifest}}, socket, dest_dir) do
    socket
    |> refresh_dest_status(dest_dir)
    |> put_flash(:error, "This export previously failed — use Retry")
    |> then(&{:noreply, &1})
  end

  defp handle_start_result({:error, reason}, socket, _dest_dir) do
    {:noreply, put_flash(socket, :error, "Could not start export: #{inspect(reason)}")}
  end

  # For S3 the job is identified by all of its inputs, so the whole form
  # must be valid before we can look up an existing job.
  defp recompute_dest_dir(socket, %{"destination" => "s3"}, changeset) do
    with {:ok, data} <- Changeset.apply_action(changeset, :validate),
         {:ok, job} <- s3_job(socket, data) do
      job.dest_dir
    else
      _error -> nil
    end
  end

  defp recompute_dest_dir(
         _socket,
         %{"storage_mountpoint" => mountpoint, "folder_name" => folder},
         _changeset
       )
       when is_binary(mountpoint) and mountpoint != "" and is_binary(folder) do
    if folder =~ @folder_name_regex, do: Path.join(mountpoint, folder)
  end

  defp recompute_dest_dir(_socket, _params, _changeset), do: nil

  defp s3_job(socket, data) do
    device = Enum.find(socket.assigns.devices, &(&1.id == data.device_id))
    remote_storage = Enum.find(socket.assigns.remote_storages, &(&1.id == data.remote_storage_id))

    if device && remote_storage do
      S3.job(
        device,
        remote_storage,
        String.to_existing_atom(data.stream),
        data[:camera_id],
        DateTime.from_naive!(data.start_date, device.timezone),
        DateTime.from_naive!(data.end_date, device.timezone)
      )
    else
      {:error, :not_found}
    end
  end

  defp refresh_dest_status(socket, nil) do
    socket
    |> assign(dest_dir: nil, job_status: :new, job_progress: nil)
    |> cancel_polling()
  end

  defp refresh_dest_status(socket, dest_dir) do
    case Export.progress(dest_dir) do
      {:ok, progress} ->
        socket
        |> assign(dest_dir: dest_dir, job_status: progress.status, job_progress: progress)
        |> then(&if progress.status == :running, do: ensure_polling(&1), else: cancel_polling(&1))

      {:error, :not_found} ->
        socket
        |> assign(dest_dir: dest_dir, job_status: :new, job_progress: nil)
        |> cancel_polling()
    end
  end

  defp ensure_polling(%{assigns: %{poll_timer: nil}} = socket) do
    if connected?(socket) do
      assign(socket, poll_timer: Process.send_after(self(), :poll_progress, @poll_interval))
    else
      socket
    end
  end

  defp ensure_polling(socket), do: socket

  defp cancel_polling(%{assigns: %{poll_timer: nil}} = socket), do: socket

  defp cancel_polling(%{assigns: %{poll_timer: ref}} = socket) do
    Process.cancel_timer(ref)
    assign(socket, poll_timer: nil)
  end

  defp export_changeset(params, socket) do
    {%{
       max_duration: @default_max_duration,
       max_file_size_mb: @default_max_file_size_mb,
       destination: "usb",
       stream: "high"
     }, @types}
    |> Changeset.cast(params, Map.keys(@types))
    |> Changeset.validate_required([:device_id, :start_date, :end_date, :destination])
    |> Changeset.validate_inclusion(:destination, ["usb", "s3"])
    |> validate_destination(socket)
    |> validate_date_order()
  end

  defp validate_destination(changeset, socket) do
    case Changeset.get_field(changeset, :destination) do
      "s3" ->
        changeset
        |> Changeset.validate_required([:remote_storage_id, :stream])
        |> Changeset.validate_inclusion(
          :stream,
          allowed_streams(socket, Changeset.get_field(changeset, :device_id)),
          message: "is not recorded by this device"
        )
        |> Changeset.validate_format(:camera_id, @folder_name_regex,
          message: "only letters, numbers, dot, dash and underscore allowed"
        )
        |> validate_kit_id(socket)

      _usb ->
        changeset
        |> Changeset.validate_required([:storage_mountpoint, :folder_name])
        |> Changeset.validate_format(:folder_name, @folder_name_regex,
          message: "only letters, numbers, dot, dash and underscore allowed"
        )
        |> Changeset.validate_number(:max_duration, greater_than: 0)
        |> Changeset.validate_number(:max_file_size_mb, greater_than: 0)
    end
  end

  defp validate_kit_id(changeset, socket) do
    id = Changeset.get_field(changeset, :remote_storage_id)

    case Enum.find(socket.assigns.remote_storages, &(&1.id == id)) do
      nil ->
        changeset

      remote_storage ->
        if S3.kit_id(remote_storage) in [nil, ""],
          do:
            Changeset.add_error(
              changeset,
              :remote_storage_id,
              "no kit id available, set one on the remote storage"
            ),
          else: changeset
    end
  end

  @doc false
  def remote_file_label(%{key: key}), do: key
  def remote_file_label(file), do: file.filename

  defdelegate upload_flags(files), to: ExNVR.Export.Manifest

  defp validate_date_order(%{valid?: false} = changeset), do: changeset

  defp validate_date_order(changeset) do
    start_date = Changeset.get_field(changeset, :start_date)
    end_date = Changeset.get_field(changeset, :end_date)

    if start_date && end_date && NaiveDateTime.compare(end_date, start_date) != :gt do
      Changeset.add_error(changeset, :end_date, "must be after start date")
    else
      changeset
    end
  end

  defp mountable_candidates(disks) do
    Enum.flat_map(disks, fn disk ->
      disk_candidate =
        if disk.fs,
          do: [%{name: disk.name, path: disk.path, fs: disk.fs, label: disk_label(disk)}],
          else: []

      part_candidates =
        for part <- disk.parts,
            part.fs,
            do: %{name: part.name, path: part.path, fs: part.fs, label: disk_label(disk)}

      disk_candidate ++ part_candidates
    end)
  end

  defp disk_label(disk), do: String.trim("#{disk.vendor} #{disk.model}")

  defp mounted_candidates(disks),
    do: Enum.filter(mountable_candidates(disks), &(&1.fs.mountpoint != nil))

  defp unmounted_candidates(disks),
    do: Enum.filter(mountable_candidates(disks), &(&1.fs.mountpoint == nil))

  @doc false
  def format_bytes(nil), do: "unknown"
  def format_bytes(bytes) when bytes >= @tib, do: "#{Float.round(bytes / @tib, 2)} TiB"
  def format_bytes(bytes) when bytes >= @gib, do: "#{Float.round(bytes / @gib, 2)} GiB"
  def format_bytes(bytes) when bytes >= @mib, do: "#{Float.round(bytes / @mib, 2)} MiB"
  def format_bytes(bytes) when bytes >= @kib, do: "#{Float.round(bytes / @kib, 2)} KiB"
  def format_bytes(bytes), do: "#{bytes} B"

  @doc false
  def percent_used(%Disk.FS{size: size, avail: avail})
      when is_integer(size) and size > 0 and is_integer(avail) do
    Float.round((size - avail) / size * 100, 1)
  end

  def percent_used(_fs), do: 0.0
end
