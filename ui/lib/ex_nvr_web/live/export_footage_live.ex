defmodule ExNVRWeb.ExportFootageLive do
  use ExNVRWeb, :live_view

  alias Ecto.Changeset
  alias ExNVR.{Devices, Disk, Export}

  @mount_root "/mnt/ex_nvr"
  @poll_interval to_timeout(second: 2)
  @folder_name_regex ~r/^[a-zA-Z0-9_.-]+$/

  @kib 1024
  @mib 1024 * 1024
  @gib 1024 * 1024 * 1024
  @tib 1024 * 1024 * 1024 * 1024

  @types %{
    device_id: :string,
    stream: :string,
    start_date: :naive_datetime,
    end_date: :naive_datetime,
    max_duration: :integer,
    max_file_size_mb: :integer,
    storage_mountpoint: :string,
    folder_name: :string
  }

  def mount(_params, _session, socket) do
    socket
    |> assign(
      devices: Devices.list(),
      disks: Disk.list_drives!(),
      dest_dir: nil,
      job_status: :new,
      job_progress: nil,
      poll_timer: nil
    )
    |> assign(export_form: to_form(export_changeset(%{}), as: "export"))
    |> then(&{:ok, &1})
  end

  def handle_event("validate", %{"export" => params}, socket) do
    changeset = params |> export_changeset() |> Map.put(:action, :validate)

    socket
    |> assign(export_form: to_form(changeset, as: "export"))
    |> refresh_dest_status(recompute_dest_dir(params))
    |> then(&{:noreply, &1})
  end

  def handle_event("submit_export", %{"export" => params}, socket) do
    changeset = params |> export_changeset() |> Map.put(:action, :insert)

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
    |> put_flash(:info, "Export stopped")
    |> then(&{:noreply, &1})
  end

  def handle_event("mount_disk", %{"part" => part_name}, socket) do
    case Enum.find(mountable_candidates(socket.assigns.disks), &(&1.name == part_name)) do
      nil -> {:noreply, socket}
      candidate -> mount_candidate(socket, candidate)
    end
  end

  def handle_info(:poll_progress, socket) do
    socket
    |> assign(poll_timer: nil)
    |> refresh_dest_status(socket.assigns.dest_dir)
    |> then(&{:noreply, &1})
  end

  def terminate(_reason, %{assigns: %{poll_timer: ref}}) when ref != nil,
    do: Process.cancel_timer(ref)

  def terminate(_reason, _socket), do: :ok

  defp mount_candidate(socket, candidate) do
    mountpoint = Path.join(@mount_root, candidate.name)

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

  defp do_start(socket, data, opts) do
    device = Enum.find(socket.assigns.devices, &(&1.id == data.device_id))
    dest_dir = Path.join(data.storage_mountpoint, data.folder_name)
    stream = String.to_existing_atom(data.stream)
    start_date = DateTime.from_naive!(data.start_date, device.timezone)
    end_date = DateTime.from_naive!(data.end_date, device.timezone)
    max_duration = Map.get(data, :max_duration)
    max_file_size_mb = Map.get(data, :max_file_size_mb)
    max_file_size = max_file_size_mb && max_file_size_mb * 1024 * 1024

    export_opts =
      [max_duration: max_duration, max_file_size: max_file_size] |> Keyword.merge(opts)

    device
    |> Export.start(stream, start_date, end_date, dest_dir, export_opts)
    |> handle_start_result(socket, dest_dir)
  end

  defp handle_start_result({:ok, _pid}, socket, dest_dir) do
    socket
    |> refresh_dest_status(dest_dir)
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

  defp recompute_dest_dir(%{"storage_mountpoint" => mountpoint, "folder_name" => folder})
       when is_binary(mountpoint) and mountpoint != "" and is_binary(folder) do
    if folder =~ @folder_name_regex, do: Path.join(mountpoint, folder)
  end

  defp recompute_dest_dir(_params), do: nil

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

  defp export_changeset(params) do
    {%{stream: "high"}, @types}
    |> Changeset.cast(params, Map.keys(@types))
    |> Changeset.validate_required([
      :device_id,
      :stream,
      :start_date,
      :end_date,
      :storage_mountpoint,
      :folder_name
    ])
    |> Changeset.validate_format(:folder_name, @folder_name_regex,
      message: "only letters, numbers, dot, dash and underscore allowed"
    )
    |> Changeset.validate_number(:max_duration, greater_than: 0)
    |> Changeset.validate_number(:max_file_size_mb, greater_than: 0)
    |> validate_date_order()
  end

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
