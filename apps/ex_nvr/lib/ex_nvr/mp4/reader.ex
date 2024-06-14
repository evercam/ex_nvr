defmodule ExNVR.MP4.Reader do
  @moduledoc false

  alias ExNVR.MP4.Reader.SamplesInfo
  alias Membrane.{AAC, Buffer, H264, H265}
  alias Membrane.MP4.Container

  @type track_id :: non_neg_integer()

  @type t :: %__MODULE__{
          fd: IO.device(),
          samples_info: SamplesInfo.t(),
          mdat_offset: non_neg_integer(),
          duration: Membrane.Time.t()
        }

  @enforce_keys [:fd, :samples_info, :duration]
  defstruct @enforce_keys ++ [mdat_offset: 0]

  @spec new(Path.t()) :: {:ok, t()} | {:error, term()}
  def new(filename) do
    with {:ok, fd} <- File.open(filename, [:read, :binary]),
         {:ok, mov_box} <- lookup_moov_box(fd),
         {box, ""} <- Container.parse!(mov_box) do
      samples_info = SamplesInfo.get_samples_info(box[:moov])
      mdat_offset = SamplesInfo.get_mdat_offset(samples_info)
      :file.position(fd, mdat_offset)

      {:ok,
       %__MODULE__{
         fd: fd,
         samples_info: samples_info,
         mdat_offset: mdat_offset,
         duration: calculate_duration(box)
       }}
    end
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{} = reader), do: File.close(reader.fd)

  @spec get_video_track(t()) :: {track_id(), H264.t() | H265.t()} | nil
  def get_video_track(%__MODULE__{} = reader),
    do: SamplesInfo.get_video_track(reader.samples_info)

  @spec read_packet(t(), track_id() | nil) :: :eof | {t(), track_id(), Buffer.t()}
  def read_packet(%__MODULE__{} = reader, track_id \\ nil) do
    case do_read_packet(reader.samples_info, track_id, reader.fd) do
      {_samples_info, nil} ->
        :eof

      {samples_info, track_id, packet} ->
        {%__MODULE__{reader | samples_info: samples_info}, track_id, packet}
    end
  end

  @spec seek_file(t(), track_id(), non_neg_integer()) :: t()
  def seek_file(%__MODULE__{samples_info: samples_info} = reader, track_id, ts) do
    index =
      samples_info.samples
      |> Enum.reverse()
      |> Enum.find_index(&(&1.track_id == track_id and &1.sync and &1.dts <= ts))

    index = if index, do: length(samples_info.samples) - index - 1, else: 0

    {to_discard, rest} = Enum.split(samples_info.samples, index)
    total_size = Enum.reduce(to_discard, 0, fn sample, size -> size + sample.size end)
    move_cursor(reader.fd, total_size)

    samples_info = %{samples_info | samples: rest}
    %__MODULE__{reader | samples_info: samples_info}
  end

  @spec duration(t()) :: Membrane.Time.t()
  def duration(%__MODULE__{duration: duration}), do: duration

  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = reader) do
    duration = reader.duration

    track_details =
      for {_track_id, sample_table} <- reader.samples_info.sample_tables do
        sample_count = sample_table.sample_count
        total_size = Enum.sum(sample_table.sample_sizes)
        duration_in_s = duration / 10 ** 9

        bitrate = round(total_size * 8 / duration_in_s)

        track_details =
          Map.merge(codec_information(sample_table.sample_description), %{bitrate: bitrate})

        if track_details.codec in [:H264, :H265],
          do: Map.put(track_details, :fps, Float.round(sample_count / duration_in_s, 2)),
          else: track_details
      end

    %{
      duration: duration,
      track_details: track_details
    }
  end

  defp lookup_moov_box(fd) do
    case IO.binread(fd, 8) do
      <<size::32, "moov">> = box_header ->
        {:ok, box_header <> IO.binread(fd, size - 8)}

      <<size::32, _box_type::binary-size(4)>> ->
        {:ok, _} = :file.position(fd, {:cur, size - 8})
        lookup_moov_box(fd)

      _other ->
        {:error, :invalid_file}
    end
  end

  defp do_read_packet(%{samples: []} = samples_info, _track_id, _fd), do: {samples_info, nil}

  defp do_read_packet(%{samples: [sample | rest]} = samples_info, track_id, fd)
       when is_nil(track_id) or sample.track_id == track_id do
    buffer =
      %Membrane.Buffer{
        payload: IO.binread(fd, sample.size),
        dts: sample.dts,
        pts: sample.pts
      }

    {%{samples_info | samples: rest}, sample.track_id, buffer}
  end

  defp do_read_packet(%{samples: [sample | rest]} = samples_info, track_id, fd) do
    move_cursor(fd, sample.size)
    do_read_packet(%{samples_info | samples: rest}, track_id, fd)
  end

  defp move_cursor(fd, amount), do: :file.position(fd, {:cur, amount})

  defp calculate_duration(box) do
    %{duration: duration, timescale: timescale} =
      Container.get_box(box, [:moov, :mvhd])[:fields]

    duration
    |> Ratio.new(timescale)
    |> Membrane.Time.seconds()
  end

  defp codec_information(%module{} = codec) when module in [H264, H265] do
    %{
      type: :video,
      codec: if(module == H264, do: :H264, else: :H265),
      codec_tag: elem(codec.stream_structure, 0),
      width: codec.width,
      height: codec.height
    }
  end

  defp codec_information(%AAC{}), do: %{type: :audio, codec: :AAC}
  defp codec_information(_codec), do: %{type: :unknow}
end
