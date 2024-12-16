defmodule ExNVR.Recordings do
  @moduledoc """
  Context to create/update/delete recordings and recordings metadata
  """
  import Ecto.Query

  alias Ecto.Multi
  alias ExMP4.{BitStreamFilter, Reader}
  alias ExNVR.Model.{Device, Recording, Run}
  alias ExNVR.Repo
  alias Phoenix.PubSub
  alias __MODULE__.VideoAssembler

  @recordings_topic "recordings"
  @default_end_date ~U(2099-01-01 00:00:00Z)
  @year_in_seconds 3_600 * 24 * 365

  @type stream_type :: :low | :high
  @type error :: {:error, Ecto.Changeset.t() | File.posix()}

  @spec create(Device.t(), Run.t(), map(), boolean()) ::
          {:ok, Recording.t(), Run.t()} | error()
  def create(%Device{} = device, %Run{} = run, params, copy_file? \\ true) do
    params = if is_struct(params), do: Map.from_struct(params), else: params

    with :ok <- copy_file(device, params, copy_file?) do
      Multi.new()
      |> Multi.insert(:run, run, on_conflict: {:replace_all_except, [:start_date]})
      |> Multi.insert(:recording, fn %{run: run} ->
        params
        |> Map.put(:filename, recording_path(device, params) |> Path.basename())
        |> Map.put(:run_id, run.id)
        |> Recording.changeset()
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{recording: recording, run: run}} ->
          broadcast_recordings_event(:new)
          {:ok, recording, run}

        {:error, _, changeset, _} ->
          {:error, changeset}
      end
    end
  end

  @spec list(map(), stream_type()) :: {:ok, {[map()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  @spec list(map()) :: {:ok, {[map()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  @spec list() :: {:ok, {[map()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}, stream_type \\ :high) do
    Recording.with_type(stream_type)
    |> Recording.list_with_devices()
    |> ExNVR.Flop.validate_and_run(params, for: Recording)
  end

  @spec get_recordings_between(binary(), DateTime.t(), DateTime.t()) :: [Recording.t()]
  @spec get_recordings_between(binary(), stream_type(), DateTime.t(), DateTime.t()) :: [
          Recording.t()
        ]
  @spec get_recordings_between(binary(), stream_type(), DateTime.t(), DateTime.t(), Keyword.t()) ::
          [Recording.t()]
  def get_recordings_between(device_id, stream_type \\ :high, start_date, end_date, opts \\ []) do
    Recording.with_type(stream_type)
    |> Recording.between_dates(start_date, end_date, opts)
    |> Recording.with_device(device_id)
    |> Repo.all()
  end

  @spec get(Device.t(), binary()) :: Recording.t() | nil
  @spec get(Device.t(), stream_type(), binary()) :: Recording.t() | nil
  def get(%Device{id: id}, stream_type \\ :high, filename) do
    Recording.with_type(stream_type)
    |> Recording.get_query(id, filename)
    |> Repo.one()
  end

  @spec exists?(Device.t(), DateTime.t()) :: boolean()
  @spec exists?(Device.t(), stream_type(), DateTime.t()) :: boolean()
  def exists?(%Device{id: id}, stream_type \\ :high, date) do
    Recording.with_device(id)
    |> Recording.with_type(stream_type)
    |> Recording.between_dates(date, date, [])
    |> Repo.exists?()
  end

  @spec details(Device.t(), Recording.t()) :: {:ok, map()} | {:error, any()}
  def details(device, recording) do
    path = recording_path(device, recording.stream, recording)

    with {:ok, stat} <- File.stat(path),
         {:ok, reader} <- Reader.new(path) do
      details = %{
        size: stat.size,
        duration: Reader.duration(reader, :millisecond),
        track_details: Reader.tracks(reader)
      }

      Reader.close(reader)

      {:ok, details}
    end
  end

  @spec snapshot(Device.t(), Recording.t(), DateTime.t(), Keyword.t()) ::
          {:ok, binary()} | {:error, any()}
  def snapshot(device, recording, datetime, opts \\ []) do
    path = recording_path(device, recording.stream, recording)
    offset = DateTime.diff(datetime, recording.start_date, :microsecond)
    method = Keyword.get(opts, :method, :before)

    with {:ok, reader} <- ExMP4.Reader.new(path) do
      track = ExMP4.Reader.tracks(reader) |> Enum.find(&(&1.type == :video))
      offset = ExMP4.Helper.timescalify(offset, :microsecond, track.timescale)
      samples = read_samples(reader, track, offset, method)

      {decoder, decoder_state} = ExNVR.Decoder.new!(track.media)

      samples
      |> Stream.map(&%Membrane.Buffer{payload: &1.payload, dts: &1.dts, pts: &1.pts})
      |> Stream.map(&decoder.decode!(decoder_state, &1))
      |> Enum.to_list()
      |> Kernel.++(decoder.flush!(decoder_state))
      |> List.flatten()
      |> List.last()
      |> then(fn buffer ->
        datetime =
          DateTime.add(
            recording.start_date,
            ExMP4.Helper.timescalify(buffer.pts, track.timescale, :microsecond),
            :microsecond
          )

        {:ok, snapshot} =
          Turbojpeg.yuv_to_jpeg(buffer.payload, track.width, track.height, 75, :I420)

        {:ok, datetime, snapshot}
      end)
    end
  end

  @spec download_footage(
          Device.t(),
          stream_type(),
          DateTime.t(),
          DateTime.t(),
          pos_integer(),
          Path.t()
        ) :: {:ok, DateTime.t()} | {:error, any()}
  def download_footage(device, stream, start_date, end_date, duration, dest) do
    end_date = end_date || @default_end_date
    duration = duration || @year_in_seconds

    # TODO: Better limit handling.
    # Each recording is check is greater than 1 minute, we have a limit of roughly 2 hours.
    case get_recordings_between(device.id, stream, start_date, end_date, limit: 120) do
      [] ->
        {:error, :not_found}

      recs ->
        footage_start_date =
          recs
          |> Enum.map(&{recording_path(device, stream, &1), &1.start_date})
          |> VideoAssembler.assemble(start_date, end_date, duration, dest)

        {:ok, footage_start_date}
    end
  end

  # Runs
  @spec list_runs(map() | Keyword.t(), stream_type()) :: [Run.t()]
  @spec list_runs(map() | Keyword.t()) :: [Run.t()]
  def list_runs(params, stream_type \\ :high) do
    Run.with_type(stream_type) |> Run.filter(params) |> Repo.all()
  end

  @spec deactivate_runs(Device.t()) :: {non_neg_integer(), nil | term()}
  def deactivate_runs(%Device{id: device_id}) do
    Repo.update_all(Run.deactivate_query(device_id), set: [active: false])
  end

  @spec recording_path(Device.t(), map()) :: Path.t()
  @spec recording_path(Device.t(), stream_type(), map()) :: Path.t()
  def recording_path(device, stream_type \\ :high, %{start_date: start_date}) do
    Path.join(
      [Device.recording_dir(device, stream_type) | ExNVR.Utils.date_components(start_date)] ++
        ["#{DateTime.to_unix(start_date, :microsecond)}.mp4"]
    )
  end

  @doc """
  Correct run and recordings dates in case of clock jumps (NTP sync)
  """
  @spec correct_run_dates(Device.t(), Run.t(), integer()) :: Run.t()
  def correct_run_dates(device, run, duration) do
    recs = Repo.all(from(r in Recording, where: r.run_id == ^run.id, order_by: r.start_date))

    Enum.each(recs, fn rec ->
      start_date = DateTime.add(rec.start_date, duration, :microsecond)
      end_date = DateTime.add(rec.end_date, duration, :microsecond)

      changeset =
        Ecto.Changeset.change(
          rec,
          %{
            start_date: start_date,
            end_date: end_date,
            filename: "#{DateTime.to_unix(start_date, :microsecond)}.mp4"
          }
        )

      new_rec = ExNVR.Repo.update!(changeset)

      File.rename!(
        ExNVR.Recordings.recording_path(device, rec),
        ExNVR.Recordings.recording_path(device, new_rec)
      )
    end)

    run
    |> Run.changeset(%{
      start_date: DateTime.add(run.start_date, duration, :microsecond),
      end_date: DateTime.add(run.end_date, duration, :microsecond)
    })
    |> Repo.update!()
  end

  @spec delete_oldest_recordings(Device.t(), integer()) ::
          :ok | {:error, Ecto.Changeset.t()}
  def delete_oldest_recordings(device, limit) do
    high_res_recordings =
      Recording.with_type(:high)
      |> Recording.oldest_recordings(device.id, limit)
      |> Repo.all()

    low_res_recordings =
      Recording.with_type(:low)
      |> Recording.before_date(List.last(high_res_recordings).end_date)
      |> Repo.all()

    delete_file = fn filename ->
      if File.exists?(filename), do: File.rm!(filename)
      :ok
    end

    ids = Enum.concat(high_res_recordings, low_res_recordings) |> Enum.map(& &1.id)
    delete_recordings_query = from(r in Recording, where: r.id in ^ids)

    Multi.new()
    |> Multi.delete_all(:recordings, delete_recordings_query)
    |> delete_recordings_multi(device, :high)
    |> delete_recordings_multi(device, :low)
    |> Multi.run(:delete_files, fn _repo, _params ->
      high_res_recordings
      |> Enum.map(&recording_path(device, &1))
      |> Enum.each(&delete_file.(&1))

      low_res_recordings
      |> Enum.map(&recording_path(device, :low, &1))
      |> Enum.each(&delete_file.(&1))

      {:ok, nil}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _params} ->
        broadcast_recordings_event(:delete)

        :telemetry.execute(
          [:ex_nvr, :recording, :delete],
          %{count: length(high_res_recordings)},
          %{device_id: device.id}
        )

      {:error, _, changeset, _} ->
        {:error, changeset}
    end
  end

  defp delete_recordings_multi(multi, device, stream_type) do
    oldest_recording_query =
      Recording.with_type(stream_type) |> Recording.oldest_recordings(device.id, 1)

    base_run_query = from(r in Run, where: r.stream == ^stream_type and r.device_id == ^device.id)
    oldest_run_query = from(r in base_run_query, order_by: r.start_date, limit: 1)

    multi
    |> Multi.one(:"oldest_recording_#{stream_type}", oldest_recording_query)
    |> Multi.run(:"runs_#{stream_type}", fn _repo, changes ->
      if recording = changes[:"oldest_recording_#{stream_type}"] do
        Repo.delete_all(from(r in base_run_query, where: r.end_date < ^recording.start_date))
      end

      {:ok, 0}
    end)
    |> Multi.one(:"oldest_run_#{stream_type}", oldest_run_query)
    |> Multi.run(:"run_#{stream_type}", fn _repo, changes ->
      if run = changes[:"oldest_run_#{stream_type}"] do
        recording = changes[:"oldest_recording_#{stream_type}"]
        Repo.update(Run.changeset(run, %{start_date: recording.start_date}))
      else
        {:ok, nil}
      end
    end)
  end

  def subscribe_to_recording_events() do
    PubSub.subscribe(ExNVR.PubSub, @recordings_topic)
  end

  defp copy_file(_device, _params, false), do: :ok

  defp copy_file(device, params, true) do
    File.cp(params.path, recording_path(device, params[:stream] || :high, params))
  end

  defp broadcast_recordings_event(event) do
    PubSub.broadcast(ExNVR.PubSub, @recordings_topic, {event, nil})
  end

  # get snapshot private functions
  defp read_samples(reader, track, offset, method) do
    {:ok, bit_stream_filter} = BitStreamFilter.MP4ToAnnexb.init(track, [])

    Reader.stream(reader, tracks: [track.id])
    |> Enum.reduce_while([], fn sample_metadata, samples ->
      cond do
        sample_metadata.dts > offset and method == :precise ->
          {:halt, [sample_metadata | samples]}

        sample_metadata.sync? ->
          {:cont, [sample_metadata]}

        sample_metadata.dts > offset ->
          {:halt, [List.last(samples)]}

        true ->
          {:cont, [sample_metadata | samples]}
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&Reader.read_sample(reader, &1))
    |> Enum.map_reduce(bit_stream_filter, &BitStreamFilter.MP4ToAnnexb.filter(&2, &1))
    |> elem(0)
  end
end
